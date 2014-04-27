package Microidium::ServerRole;

# VERSION

use PryoNet::Server;

use Moo::Role;

sub run {
    my $PORT = 19366;
    my $pryo = PryoNet::Server->new;
    $pryo->listen($PORT);
    $pryo->loop->run;
    return;
}

1;
