package App::Termcast::Connector;
use Moose;
# ABSTRACT: abstract away your termcast server communication

use IO::Socket::UNIX;
use JSON ();
use Try::Tiny;

=attr manager_socket_path

The path to the listening manager UNIX socket that L<App::Termcast::Server>
creates.

=cut

has manager_socket_path => (
    is       => 'ro',
    isa      => 'Str',
);

=attr manager_socket

UNIX socket that connects to L<App::Termcast::Server>'s manager socekt. By
default this is automatically built using the C<manager_socket_path> attribute
for the path.

=cut

has manager_socket => (
    is      => 'ro',
    isa     => 'IO::Socket::UNIX',
    builder => '_build_manager_socket',
    lazy    => 1,
);

sub _build_manager_socket {
    my $self = shift;

    my $socket = IO::Socket::UNIX->new(
        Peer => $self->manager_socket_path,
    ) or die $!;

    return $socket;
}

=attr sessions_cb

When C<< <$connector->request_sessions> >> is called`, the server will respond
with the sessions available. This callback will be invoked when a response
comes back. The C<App::Termcast::Connector> object, followed by the list
of sessions will be passed into the callback.

=method register_sessions_callback

Assigns a coderef to the C<sessions_cb> attribute.

=cut

has sessions_cb => (
    is     => 'rw',
    isa    => 'CodeRef',
    writer => 'register_sessions_callback',
);

=attr connect_cb

When a new broadcaster connects to the server, it lets all app connections know.
In this case, the C<connect_cb> callback is called. The connector object
followed by a hashref of the connection data is passed into this callback.

=method register_connect_callback

Assigns a coderef to the C<connect_cb> attribute.

=cut

has connect_cb => (
    is     => 'ro',
    isa    => 'CodeRef',
    writer => 'register_connect_callback',
);

=attr disconnect_cb

When a broadcaster disconnects to the server, it lets all app connections know.
In this case, the C<disconnect_cb> callback is called. The connector object
followed by session ID (Str) is passed into this callback.

=method register_disconnect_callback

Assigns a coderef to the C<disconnect_cb> attribute.

=cut

has disconnect_cb => (
    is     => 'ro',
    isa    => 'CodeRef',
    writer => 'register_disconnect_callback',
);

=attr metadata_cb

When a broadcaster makes certain changes to its terminal, the server lets all
app connections know.  In this case, the C<metadata_cb> callback is called.
The connector object, session ID (Str), and the data associated with the
(HashRef) are passed into this callback.

=method register_metadata_callback

Assigns a coderef to the C<metadata_cb> attribute.

=cut

has metadata_cb => (
    is     => 'ro',
    isa    => 'CodeRef',
    writer => 'register_metadata_callback',
);

has json => (
    is  => 'ro',
    isa => 'JSON',
    default => sub { JSON->new },
);

=method request_sessions

  Usage: $connector->request_sessions

or:
  
  Usage: $connector->request_sessions($socket);

Sends a request for a list of the current Termcast sessions. When a response
coems back, the C<sessions_cb> callback will be triggered.

If you chose not to pass in a C<manager_socket_path> param, you can request
termcast sessions by passing in your own socket.

=cut

sub request_sessions {
    my $self = shift;
    my $socket = shift || $self->manager_socket;

    my $req_string = JSON::encode_json({request => 'sessions'});
    $socket->syswrite($req_string);
}

=method dispatch

  Usage: $connector->dispatch($input);

or:

  Usage: $connector->dispatch($ref, decoded => 1);

When you get any input from the Termcast server's manager socket, you pass it
in to this method.

You can pass C<< <decoded => 1> >> if you are using something that can already
decodes JSON for you, such as L<AnyEvent::Handle>'s C<push_write>. Otherwise
C<dispatch> will do the decoding for you.

=cut

sub dispatch {
    my $self   = shift;
    my ($json) = shift;
    my %args   = @_;

    my @data = $args{decoded} ? ($json) : $self->json->incr_parse($json)
        or return;

    $self->_handle_ref($_) for @data;
}

sub _decode {
    my $self = shift;
    my ($json) = @_;

    return try { $self->json->incr_parse($json) }
        catch { warn $_; $self->json->incr_skip };
}


sub _handle_ref {
    my $self = shift;
    my ($data) = @_;

    if ($data->{notice}) {
        $self->handle_notice($data);
    }
    elsif ($data->{response}) {
        $self->handle_response($data);
    }
}

sub handle_notice {
    my $self = shift;
    my $data = shift;

    if ($data->{notice} eq 'connect') {
        if ($self->connect_cb) {
            $self->connect_cb->($self, $data->{connection});
        }
    }
    elsif ($data->{notice} eq 'disconnect') {
       if ($self->disconnect_cb) {
           $self->disconnect_cb->($self, $data->{session_id});
       }
    }
    elsif ($data->{notice} eq 'metadata') {
        if ($self->metadata_cb) {
            $self->metadata_cb->($self, $data->{session_id}, $data->{metadata});
        }
    }
}

sub handle_response {
    my $self = shift;
    my $data = shift;

    if ($data->{response} eq 'sessions') {
        my @sessions = @{ $data->{sessions} };
        if (@sessions) {
            $self->sessions_cb->($self, @sessions);
        }
    }
}

=method make_socket

  Usage: $connector->dispatch($input);

or:

  Usage: $connector->dispatch($ref, decoded => 1);

When you get any input from the Termcast server's manager socket, you pass it
in to this method.

You can pass C<< <decoded => 1> >> if you are using something that can already
decodes JSON for you, such as L<AnyEvent::Handle>'s C<push_write>. Otherwise
C<dispatch> will do the decoding for you.

=cut

sub make_socket {
    my $self = shift;
    my ($args) = @_;

    my $socket_path = $args->{socket};

    my $socket = IO::Socket::UNIX->new(
        Peer => $args->{socket},
    ) or die $!;

    return $socket;
}

no Moose;

1;
