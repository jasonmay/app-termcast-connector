package App::Termcast::Connector;
use Moose;
# ABSTRACT: abstract away your termcast server communication

use IO::Socket::UNIX;
use JSON ();
use Try::Tiny;

has manager_socket_path => (
    is       => 'ro',
    isa      => 'Str',
);

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

sub request_sessions {
    my $self = shift;
    my $socket = shift || $self->manager_socket;

    my $req_string = JSON::encode_json({request => 'sessions'});
    $socket->syswrite($req_string);
}

has sessions_cb => (
    is     => 'rw',
    isa    => 'CodeRef',
    writer => 'register_sessions_callback',
);

has connect_cb => (
    is     => 'ro',
    isa    => 'CodeRef',
    writer => 'register_connect_callback',
);

has disconnect_cb => (
    is     => 'ro',
    isa    => 'CodeRef',
    writer => 'register_disconnect_callback',
);

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
