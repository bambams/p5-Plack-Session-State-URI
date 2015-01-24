use strict;
use warnings;

use Data::Dumper;
use File::Temp;
use HTTP::Request::Common;
use Plack::Builder;
use Plack::Request;
use Plack::Session::State::URI;
use Plack::Session::Store::File;
use Plack::Session;
use Plack::Test;
use Readonly;
use Test::Simple tests => 10;

sub escape_js_string {
    my ($fake_form) = @_;

    $fake_form =~ s/"/\\"/g;

    return $fake_form;
}

Readonly::Scalar my $fake_form => '<form id="fake"></form>';
Readonly::Scalar my $bad_attr => qq/data-breaking-attribute='$fake_form'/;
Readonly::Scalar my $js_str_fake_form => escape_js_string($fake_form);
Readonly::Scalar my $sid => 'sid';
Readonly::Scalar my $base_re => qr/.*fake.*\n?.*$sid/;

Readonly::Scalar my $html => <<EOF;
<style type="text/css" $bad_attr></form>'>
    /*css $fake_form */
</style>
<script type="text/javascript" $bad_attr>
    <!--
    var html = "$js_str_fake_form";
    // $fake_form
    /*js $fake_form */
    -->
</script>
<form id="real" $bad_attr>
    <!-- $fake_form -->
    <label for="name" $bad_attr>Name:</label>
    <input type="text" id="name" name="name" $bad_attr />
</form>
EOF

my $app = builder {
    my $dir = File::Temp->newdir('XXXXXXXX',
            CLEANUP => 1,
            TEMPDIR => 1,
            TMPDIR => 1);

    my $store = Plack::Session::Store::File->new(dir => $dir),
    my $state = Plack::Session::State::URI->new(session_key => $sid);

    enable 'Session', store => $store, state => $state;

    sub {
        my ($env) = @_;
        my $req = Plack::Request->new($env);
        my $session = Plack::Session->new($env);

        if (defined $req->param('data')) {
            $session->set('data', $req->param('data'));
        }

        my $data = $session->get('data');

        $data = '' unless defined $data;

        if (my $url = $req->param('url')) {
            [
                302,
                ['Location', $url],
                ['']
            ];
        } else {
            [
                200,
                ['Content-Type', 'text/html; charset="UTF-8"'],
                [$html]
            ]
        }
    }
};

sub test_result {
    my ($desc, $result, $neg) = @_;

    if ($neg) {
        $result = !$result;
    }

    ok $result, $desc;
}

sub test_lambda {
    my ($desc, $lambda, $neg) = @_;

    local $_;

    my $result = $lambda->();

    test_result($desc, $result, $neg);
}

sub test_match {
    my ($desc, $re, $neg) = @_;

    my $content = $_;

    local $_ = $content;

    my @matches = $content =~ /($re)/;

    my $result = @matches;

    test_result($desc, $result, $neg);
}

test_psgi $app, sub {
    my ($cb) = @_;

    my $res = $cb->(GET '/');

    my $content = $res->content;

    local $_ = $content;

    test_match(
            'embedded HTMl <form> in <style> attribute',
            qr/<style$base_re/,
            1);

    test_match(
            'embedded HTML <form> in CSS /**/ comment',
            qr{/\*css$base_re},
            1);

    test_match(
            'embedded HTML <form> in <script> attribute',
            qr/<script$base_re/,
            1);

    test_match(
            'embedded HTML <form> in JavaScript string',
            qr/(var$base_re)/,
            1);

    test_match(
            'embedded HTML <form> in JavaScript line comment',
            qr{//$base_re},
            1);

    test_match(
            'embedded HTML <form> in JavaScript block comment',
            qr{/\*js$base_re},
            1);

    test_match(
            'embedded HTML <form> in <form> attribute',
            qr|
                <form\ id="real"
                .*?
                <form\ id="fake">
                [\n\s]*
                <input
                [^>]+
                $sid
            |x,
            1);

    test_match(
            'embedded HTML <form> in <form> <label> attribute',
            qr/<label$base_re/,
            1);

    test_match(
            'embedded HTML <form> in <form> <input> attribute',
            qr/<input.*id="name"$base_re/,
            1);

    test_lambda(
            'real <form> has session identifier hidden <input>' =>
            sub {
                my ($content) = @_;

                require HTML::TreeBuilder::XPath;

                my $tree = HTML::TreeBuilder::XPath->new_from_content($content);

                my $xpath = sprintf q{//form//input[@name='%s']}, $sid;

                my ($node) = $tree->findnodes($xpath);

                return $node;
            });
};
