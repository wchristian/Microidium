package PryoNet::Server;

# VERSION

use Moo;

with "PryoNet::LoopRole";
with 'PryoNet::ServerRole';
with "PryoNet::ListenersRole";
with 'PryoNet::SerializationRole';

1;
