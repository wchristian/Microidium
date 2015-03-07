package PryoNet::Client;

use strictures;

# VERSION

use Moo;

with "PryoNet::LoopRole";
with "PryoNet::ConnectionRole";
with "PryoNet::ListenersRole";
with 'PryoNet::ClientRole';
with 'PryoNet::SerializationRole';

1;
