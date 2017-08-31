=head1 NAME

RT::Integration::ScreenConnect


=cut

use strict;
use warnings;

package RT::Integration::ScreenConnect;

use JSON;
use HTTP::Request;
use LWP::UserAgent;

=head1 NAME

RT::Integration::ScreenConnect - A module enabling integration
between RT and the ScreenConnect (now ConnectWise Control) remote
support platform.

=head1 SYNOPSIS

  use RT::Integration::ScreenConnect;

=head1 DESCRIPTION

This module enables RT to create support sessions in a ScreenConnect
instance, by working in conjunction with a corresponding extension
installed in the ScreenConnect instance.

=head1 VARIABLES

The following must be set in your RT site config for the integration
to work:

=over

=item * C<ScreenConnectBaseURL>

The base URL of your ScreenConnect instance. For a self-host instance
this might be C<https://screenconnect.example.com>; for a cloud-hosted
instance C<https://example.screenconnect.com>.

=item * C<ScreenConnectRTExtensionGUID>

The GUID assigned by your ScreenConnect instance to the RT extension.
This value will be different for each ScreenConnect instance, and will
change if you uninstall and reinstall the RT extension.

=item * C<ScreenConnectAPIToken>

The API token configured in the RT extension settings of your
ScreenConnect instance. May be any string, but it must match on both
sides.

=back

=head1 METHODS

=head2 createSupportSession( $ticketId )

Tries to create a support session in ScreenConnect. Returns a
status along with the guest URL and host URL provided by
ScreenConnect.

=cut

sub createSupportSession {
    my $ticketId = shift;

    my $ticket = RT::Ticket->new(RT->SystemUser);
    $ticket->Load($ticketId);
    return (0, undef, undef) unless ($ticket->Id);

    my $scBaseUrl = RT->Config->Get("ScreenConnectBaseURL");
    if (! defined $scBaseUrl || $scBaseUrl !~ /^https?:/) {
        $RT::Logger->error( "ScreenConnectBaseURL is not set in RT config, or does not look like an HTTP(S) URL. Aborting.");
        return (0, undef, undef);
    }
    my $scExtenGuid = RT->Config->Get("ScreenConnectRTExtensionGUID");
    if (! defined $scExtenGuid || $scExtenGuid !~ /^[0-9A-Fa-f-]{36}$/) {
        $RT::Logger->error( "ScreenConnectRTExtensionGUID is not set in RT config, or does not look like a GUID. Aborting.");
        return (0, undef, undef);
    }
    my $scApiToken = RT->Config->Get("ScreenConnectAPIToken");
    if (! defined $scApiToken) {
        $RT::Logger->error( "ScreenConnectAPIToken is not set in RT config. Aborting.");
        return (0, undef, undef);
    }
    my $scPostUrl = "${scBaseUrl}/App_Extensions/${scExtenGuid}/Service.ashx/CreateRequestTrackerIntegratedSupportSession";
    my @scPostData = ($ticket->Id, $ticket->OwnerObj->RealName, $ticket->Subject);

    # Do the POST
    my $req = HTTP::Request->new( 'POST', $scPostUrl );
    $req->header( 'Content-type' => 'application/json' );
    $req->header( 'X-Api-Token' => $scApiToken );
    $req->content( encode_json(\@scPostData) );
    my $lwp = LWP::UserAgent->new;
    my $response = $lwp->request( $req );

    if (! $response->is_success) {
        $RT::Logger->error("Failed to create remote support session. ${scPostUrl} with " . encode_json(\@scPostData) . " responded: " . $response->status_line);
        return (0, undef, undef);
    }

    my $scResponse = decode_json($response->decoded_content);
    my $guestUrl = $scResponse->{guestUrl};
    my $hostUrl = $scResponse->{hostUrl};

    if ((! defined $guestUrl) || (!defined $hostUrl)) {
        $RT::Logger->error("ScreenConnect response lacks guest and/or host URL: " . $response->decoded_content);
        return (0, undef, undef);
    }

    return (1, $guestUrl, $hostUrl);
}

1;
