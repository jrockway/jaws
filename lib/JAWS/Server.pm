use MooseX::Declare;

class JAWS::Server with Plack::Component::Role {
    use AnyEvent;
    use AnyEvent::HTTP;
    use URI;

    # this actually makes a noticeable speed difference
    sub call {
        my ($self, $env) = @_;
        my $url = $env->{PATH_INFO};
        $url =~ s{^/}{};
        $url = "http://$url" if $url !~ m{^\w+://};

        my $uri = URI->new( $url );
        die "invalid URI" unless $uri->scheme eq 'http';

        return sub {
            my $respond = shift;

            my %req_headers = map {
                my $k = $_;
                $k =~ s/^HTTP_//;
                $k =~ tr/_/-/;
                lc $k => $env->{$_} }
              grep { /^HTTP/ } keys %$env;

            $req_headers{host} = $uri->host;

            my $writer;
            http_get "$uri", headers => \%req_headers,
              on_body => sub {
                  my ($body, $headers) = @_;

                  if ($headers->{Status} >= 590) { # internal error
                      $respond->([ $headers->{Status}, [], [ $headers->{Reason} ] ]);
                      return 0;
                  }

                  $writer ||= $respond->([ $headers->{Status}, [ %$headers ]]);
                  $writer->write($body);
                  return 1;
              },
              sub { $writer->close };

            return;
        };
    }
}
