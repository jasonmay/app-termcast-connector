#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use App::Termcast::Connector;

use JSON ();

my $connect_ok    = 0;
my $disconnect_ok = 0;
my $metadata_ok   = 0;
my $sessions_ok   = 0;

my $connector     = App::Termcast::Connector->new(
    connect_cb    => sub { $connect_ok = 1 },
    disconnect_cb => sub { $disconnect_ok = 1 },
    metadata_cb   => sub { $metadata_ok = 1 },
    sessions_cb   => sub { $sessions_ok = 1 },
);

my $connect_json = JSON::encode_json(
    {
        notice     => 'connect',
        connection => {
            session_id => 'foo',
        }
    }
);
$connector->dispatch($connect_json);

my $disconnect_json = JSON::encode_json(
    {
        notice     => 'disconnect',
        session_id => 'foo',
    }
);

my $metadata_json = JSON::encode_json(
    {
        notice     => 'metadata',
        session_id => 'foo',
        metadata => {
            foo => 'bar',
        }
    }
);

my $sessions_json = JSON::encode_json(
    {
        response     => 'sessions',
        sessions => [
            {
                session_id => 'foo',
            },
        ],
    }
);

$connector->dispatch($_) for $connect_json,
                             $disconnect_json,
                             $metadata_json,
                             $sessions_json;

ok $connect_ok,    'connect cb called';
ok $disconnect_ok, 'disconnect cb called';
ok $metadata_ok,   'metadata cb called';
ok $sessions_ok,   'metadata cb called';

done_testing;
