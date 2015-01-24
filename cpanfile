requires 'perl', '5.008001';

requires 'Plack';
requires 'Plack::Middleware::Session';
requires 'HTML::StickyQuery';

on test => sub {
    requires 'Test::More';
    requires 'HTML::TreeBuilder::XPath';
    requires 'HTTP::Request::Common';
    requires 'Readonly';
};
