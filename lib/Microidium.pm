package Microidium;

# VERSION
# ABSTRACT: an asteroid-like game

=head1

=for HTML <p><img src="https://dl.dropboxusercontent.com/u/10190786/microidium.png" /></p>

Sounds made with http://www.bfxr.net/

=cut

use Moo;

with "Microidium::LogicRole";
with "Microidium::ClientRole";
with "Microidium::SDLRole";

1;
