package Microidium::ServerRole;

# VERSION

use PryoNet::Server;
use IO::Async::Timer::Periodic;
use Time::HiRes 'time';

use Moo::Role;

sub run {
    my $PORT = 19366;
    my $pryo = PryoNet::Server->new;
    $pryo->listen( $PORT );

    my $tick = 0;

    my $timer = IO::Async::Timer::Periodic->new(
        interval => 0.016,
        on_tick  => sub {
            $tick++;
            $pryo->write( $tick . " " . time . " You've had a minute" );
        },
    );

    $timer->start;
    $pryo->loop->add( $timer );
    $pryo->loop->run;
    return;
}

1;
