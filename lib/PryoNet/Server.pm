package PryoNet::Server;

use strictures;

# VERSION

use Moo;

with "PryoNet::LoopRole";
with 'PryoNet::ServerRole';
with "PryoNet::ListenersRole";
with 'PryoNet::SerializationRole';

1;
