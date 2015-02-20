package Microidium;

# VERSION
# ABSTRACT: an asteroid-like game

=head1 DESCRIPTION

=for HTML <p><a href="http://www.youtube.com/watch?v=KoLMoc5RvQ4"><img src="http://img.youtube.com/vi/KoLMoc5RvQ4/0.jpg" /></a></p>

This has a number of dependencies that should all be available from CPAN. Run
C<perl Makefile.PL> to get a list of dependencies that you still need to
install.

=head1 RESOURCES

Sounds made with http://www.bfxr.net/

Font texture made with http://www.codehead.co.uk/cbfg/

=cut

use Moo;

with "Microidium::LogicRole";
with "Microidium::ClientRole";
with "Microidium::SDLRole";

1;
