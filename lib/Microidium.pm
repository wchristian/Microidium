package Microidium;

# VERSION
# ABSTRACT: an asteroid-like game

=head1 DESCRIPTION

=for HTML <p><a href="https://www.youtube.com/watch?v=DWbOnrrJGNI"><img src="http://img.youtube.com/vi/DWbOnrrJGNI/0.jpg" /></a></p>

This has a number of dependencies that should all be available from CPAN. Run
C<perl Makefile.PL> to get a list of dependencies that you still need to
install.

=head1 INSTALLATION

It might be necessary to download Nvidia Inspector, use the Profile Settings,
find the perl process, and set "Enable application for Optimus" to
SHIM_RENDERING_MODE_USER_EDITABLE.

Running this and using the new hardlink can also help to result in usage of the
correct GPU:

    mklink /H gpu-chrome.exe chrome.exe

To install the dependency L<Acme::MITHALDU::BleedingOpenGL> on Apple machines
you might need to step in manually and run Makefile.PL with this parameter:

    perl Makefile.PL interface=FREEGLUT

=head1 THANKS

Thanks go to these people, in no particular order, for their respective
contributions. I probably forgot a bunch. I'll add more as they come to mind, or
you can just poke me.

L<Vlambeer|http://www.vlambeer.com/> for making
L<Luftrausers|http://luftrausers.com/> and inspiring me to start this project,
as well as for talking openly about their
L<development process|https://www.youtube.com/watch?v=AJdEqssNZ-U>.

L<Getty|https://metacpan.org/author/GETTY> for the name.

L<SVatG|http://demogroup.vc/> for emotional support and graphics programming
knowledge.

L<Paul Evans|https://metacpan.org/author/PEVANS> and other maintainers
L<IO::Async>, used for networking.

L<Ingy döt Net|https://metacpan.org/author/INGY> and other maintainers for
L<Inline::Module> and L<Inline::C>, used to provide slow Perl math as blazing
fast XS.

L<Chris Marshall|https://metacpan.org/author/CHM> and other maintainers for
L<OpenGL>, used for graphics, and L<PDL>, used for matrix math.

L<Tobias Leich (FROGGS)|https://metacpan.org/author/FROGGS> and other
maintainers for L<SDL>, used to handle window manager chrome, interactivity and
audio.

L<Etay Meiri|http://ogldev.atspace.co.uk/> and
L<Jason L. McKesson|http://www.arcsynthesis.org/gltut/> for writing OpenGL
tutorials that helped me start this off in a modern way.

L<Nathan Sweet|https://github.com/NathanSweet> for his Java library
L<kyronet|https://github.com/EsotericSoftware/kryonet> which i used as an
inspiration for the networking parts.

The L<Starsiege: Tribes|http://en.wikipedia.org/wiki/Starsiege:_Tribes> and
L<Halo: Reach|http://en.wikipedia.org/wiki/Halo:_Reach> development teams for
publicly talking about and explaining their respective networking models:
L<The Tribes Networking Model|http://gamedevs.org/uploads/tribes-networking-model.pdf>
and L<I Shot You First!|http://www.gdcvault.com/play/1014345/I-Shot-You-First-Networking>

Charon for his delightful music track "vecinec22".

L<wrl (william light)|https://github.com/wrl> for talking me through a bunch of
OpenGL rendering internals.

=head1 RESOURCES

Sounds made with http://www.bfxr.net/

Font texture made with http://www.codehead.co.uk/cbfg/

To be inspected for inspiration: http://www.xpilot.org/development/

=cut

use Moo;

with "Microidium::LogicRole";
with "Microidium::ClientRole";
with "Microidium::SDLRole";
with "Microidium::ClientCameraRole";

1;
