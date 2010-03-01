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

        my %req_headers = map {
            my $k = $_;
            $k =~ s/^HTTP_//;
            $k =~ tr/_/-/;
            lc $k => $env->{$_} }
          grep { /^HTTP/ } keys %$env;

        $req_headers{host} = $uri->host;

        my $body_cb = Coro::rouse_cb;
        http_get "$uri", want_body_handle => 1, headers => \%req_headers, $body_cb;

        return sub {
            my $respond = shift;

            my ($body_fh, $headers) = Coro::rouse_wait($body_cb);
            if($headers->{Status} >= 590){ # internal error
                $respond->([ $headers->{Status}, [], [ $headers->{Reason} ] ]);
                return;
            }

            my $writer = $respond->([ 200, [ %$headers ]]);

            eval {
                my $done = Coro::rouse_cb;
                $body_fh->on_error(sub { $writer->close; $done->(); });
                $body_fh->on_eof(sub { $writer->close; $done->(); });
                $body_fh->on_read(sub { $writer->write( delete $body_fh->{rbuf} ) });

                Coro::rouse_wait($done);
                $body_fh->destroy;
            };
            if($@){
                $writer->write("FAIL: $@");
                return;
            }
        };
    }
}
