# $Id: Admin.pm,v 1.2 1998/12/18 01:18:18 eric Exp $

package IMAP::Admin;

use strict;
use Carp;
use IO::Select;
use IO::Socket;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '0.5';

sub new {
    my $class = shift;
    my $self = {};

    bless $self, $class;
    if ((scalar(@_) % 2) != 0) {
	croak "$class called with incorrect number of arguments";
    }
    while (@_) {
	my $key = shift(@_);
	my $value = shift(@_);
	$self->{$key} = $value;
    }
    $self->{'CLASS'} = $class;
    $self->_initialize;
    return $self;
}

sub _initialize {
    my $self = shift;

    if (!defined($self->{'Server'})) {
	croak "$self->{'CLASS'} not initialized properly : Server parameter missing";
    }
    if (!defined($self->{'Port'})) {
	$self->{'Port'} = 143; # default imap port;
    }
    if (!defined($self->{'Login'})) {
	croak "$self->{'CLASS'} not initialized properly : Login parameter missing";
    }
    if (!defined($self->{'Password'})) {
	croak "$self->{'CLASS'} not initialized properly : Password parameter missing";
    }

    if (!eval {$self->{'Socket'} = IO::Socket::INET->new(PeerAddr => $self->{'Server'},
							 PeerPort => $self->{'Port'},
							 Proto => 'tcp',
							 Reuse => 1); })
    {
	croak "$self->{'CLASS'} couldn't establish a connection to $self->{'Server'}";
    }
    my $fh = $self->{'Socket'};
    $_ = <$fh>; # get Banner
    if (!/\* OK/) {
	$self->close;
	croak $_;
    }
    print $fh "try login $self->{'Login'} $self->{'Password'}\n";
    $_ = <$fh>;
    if (/Login incorrect/) {
	$self->close;
	croak "$self->{'CLASS'}: Login incorrect while connecting to $self->{'Server'}";
    } elsif (/try OK/) {
	return;
    } else {
	croak "$self->{'CLASS'}: Unknown error -- $_";
    }
}

sub _error {
    my $self = shift;
    my $func = shift;
    my @error = @_;

    $self->{'Error'} = join(" ",$self->{'CLASS'}, "[", $func, "]:", @error);
}

sub close {
    my $self = shift;
    my $fh = $self->{'Socket'};
    
    print $fh "try logout\n";
    $_ = <$fh>;
    close($self->{'Socket'});
    delete $self->{'Socket'};
}

sub create {
    my $self = shift;

    if (scalar(@_) != 1) {
	$self->_error("create", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("create", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    print $fh "try CREATE $mailbox\n";
    $_ = <$fh>;
    if (/^try OK/) {
	$self->{'Error'} = 'No Errors';
	return 0;
    } else {
	$self->_error("create", "couldn't create", $mailbox, ":", $_);
	return 1;
    }
}

sub delete {
    my $self = shift;

    if (scalar(@_) != 1) {
	$self->_error("delete", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("delete", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    print $fh "try DELETE $mailbox\n";
    $_ = <$fh>;
    if (/^try OK/) {
	$self->{'Error'} = 'No Errors';
	return 0;
    } else {
	$self->_error("delete", "couldn't delete", $mailbox, ":", $_);
    }
}

sub get_quota { # returns a hash or undef
    my $self = shift;
    my (%quota, @info);

    if (scalar(@_) != 1) {
	$self->_error("get_quota", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("get_quota", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    print $fh "try GETQUOTA $mailbox\n";
    $_ = <$fh>;
    while (/^\* QUOTA/) {
	tr/\)\(//d;
	@info = (split(' '))[2,5];
	$quota{$info[0]} = $info[1];
	$_ = <$fh>;
    }
    if (/^try OK/) {
	return %quota;
    } else {
	$self->_error("get_quota", "couldn't get quota for", $mailbox, ":", $_);
	return;
    }
}

sub set_quota {
    my $self = shift;

    if (scalar(@_) != 2) {
	$self->_error("set_quota", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    my $quota = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("set_quota", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    print $fh "try SETQUOTA $mailbox (STORAGE $quota)\n";
    $_ = <$fh>;
    if (/^try OK/) {
	$self->{'Error'} = "No Errors";
	return 0;
    } else {
	$self->_error("set_quota", "couldn't set quota for", $mailbox, ":", $_);
	return 1;
    }
}

sub get_acl { # returns a hash or undef
    my $self = shift;
    my (@info, %acl, $item);

    if (scalar(@_) != 1) {
	$self->_error("get_acl", "incorrect number of arguments");
	return;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("get_acl", "no connection open to ", $self->{'Server'});
	return;
    }
    my $fh = $self->{'Socket'};
    print $fh "try GETACL $mailbox\n";
    $_ = <$fh>;
    while (/^\* ACL/) {
	@info = split(' ',$_,4);
	$acl{$info[2]} = $info[3];
	$_ = <$fh>;
    }
    if (/^try OK/) {
	return %acl;
    } else {
	$self->_error("get_acl", "couldn't get acl for", $mailbox, ":", $_);
	return;
    }
}

sub set_acl {
    my $self = shift;
    my ($id, $acl);

    if (scalar(@_) < 2) {
	$self->_error("set_acl", "too few arguments");
	return 1;
    }
    if ((scalar(@_) % 2) == 0) {
	$self->_error("set_acl", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("set_acl", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    while(@_) {
	$id = shift;
	$acl = shift;
	print $fh "try SETACL $mailbox $id $acl\n";
	$_ = <$fh>;
	if (!/^try OK/) {
	    $self->_error("set_acl", "couldn't set acl for", $mailbox, $id, 
			 $acl, ":", $_);
	    return 1;
	}
    }
    $self->{'Error'} = 'No Errors';
    return 0;
}

sub delete_acl {
    my $self = shift;
    my ($id, $acl);

    if (scalar(@_) < 1) {
	$self->_error("delete_acl", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("delete_acl", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    while(@_) {
	$id = shift;
	print $fh "try DELETEACL $mailbox $id\n";
	$_ = <$fh>;
	if (!/^try OK/) {
	    $self->_error("delete_acl", "couldn't delete acl for", $mailbox,
			  $id, $acl, ":", $_);
	    return 1;
	}
    }
    return 0;
}

sub list { # wild cards are allowed, returns array or undef
    my $self = shift;
    my (@info, @mail);

    if (scalar(@_) != 1) {
	$self->_error("list", "incorrect number of arguments");
	return;
    }
    my $list = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("list", "no connection open to", $self->{'Server'});
	return;
    }
    my $fh = $self->{'Socket'};
    print $fh "try LIST $list $list\n";
    $_ = <$fh>;
    while (/\* /) { # danger danger (could lock up needs timeout)
	@info = split(' ');
	push @mail, $info[$#info];
	$_ = <$fh>;
    }
    if (/^try OK/) {
	return @mail;
    } else {
	$self->_error("list", "couldn't get list for", $list, ":", $_);
	return;
    }
}


# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

IMAP::Admin - Perl module for basic IMAP server administration

=head1 SYNOPSIS

  use IMAP::Admin;
  
  $imap = IMAP::Admin->new('Server' => 'name.of.server.com',
			   'Port' => port# (143 is default),
			   'Login' => 'login_of_imap_administrator',
			   'Password' => 'password_of_imap_adminstrator');

  $err = $imap->create("user.bob");
  if ($err != 0) {
    print "$imap->{'Error'}\n";
  }
  $err = $imap->delete("user.bob");

  %quota = $imap->get_quota("user.bob");
  $err = $imap->set_quota("user.bob", 10000);

  %acl = $imap->get_acl("user.bob");
  $err = $imap->set_acl("user.bob", "admin", "lrswipdca", "joe", "lrs");
  $err = $imap->delete_acl("user.bob", "joe", "admin");
 
  @list = $imap->list("user.bob");
  @list = $imap->list("user.b*");

  

=head1 DESCRIPTION

IMAP::Admin provides basic IMAP server adminstration.  It provides functions for creating and deleting mailboxes and setting various information such as quotas and access rights.

It's interface should, in theory, work with any RFC compliant IMAP server, but I currently have only tested it against Carnegie Mellon University's Cyrus IMAP.

Operationally it opens a socket connection to the IMAP server and logs in with the supplied login and password.  You then can call any of the functions to perform their associated operation.


=head2 MAILBOX FUNCTIONS

RFC2060 commands.  These should work with any RFC2060 compliant IMAP mail servers.

create makes new mailboxes.  Cyrus IMAP, for normal mailboxes, has the user. prefix.
create returns a 0 on success or a 1 on failure.  An error message is placed in the
object->{'Error'} variable on failure.

delete destroys mailboxes.
delete returns a 0 on success or a 1 on failure.  An error message is placed in the
object->{'Error'} variable on failure.

list lists mailboxes.  list accepts wildcard matching

Currently create and delete only take one argument.  This will probably change in the future to allow for mass creation/destruction.

=head2 QUOTA FUNCTIONS

NOT RFC2060 commands.  I believe these are specific to Cyrus IMAP.

get_quota retrieves quota information.  It returns a hash on success and undef on failure.  In the event of a failure the error is place in the object->{'Error'} variable.

get_quota takes only one argument, but this will probably change to multiple and/or wildcard matching.

set_quota sets the quota.  The number is in kilobytes so 10000 is approximately 10Meg.
set_quota returns a 0 on success or a 1 on failure.  An error message is placed in the object->{'Error'} variable on failure.

=head2 ACCESS CONTROL FUNCTIONS

NOT RFC2060 commands.  I believe these are specific to Cyrus IMAP.

get_acl retrieves acl information.  It returns a hash on success and under on failure.  In the event of a failure the error is placed in the object->{'Error'} variable.

set_acl set acl information for a single mailbox.  You can specify more the one user's rights on the same set call.  It returns a 0 on success or a 1 on failure.  An error message is placed in the object->{'Error'} variable on failure.

delete_acl removes acl information on a single mailbox for the given users.  You can specify more the one users rights to be removed in the same delete_acl call.  It returns a 0 on success or a 1 on failure.  An error message is placed int the object->{'Error'} variable on failure.

The access control information is from Cyrus IMAP.
  read   = "lrs"
  post   = "lrsp"
  append = "lrsip"
  write  = "lrswipcd"
  all    = "lrswipcda"

=head1 KNOWN BUGS

Currently all the of the socket traffic is handled via prints and <>.  This means that some of the calls could hang if the socket connection is broken.  Eventually the will be properly selected and timed.

=head1 CVS REVISION

$Id: Admin.pm,v 1.2 1998/12/18 01:18:18 eric Exp $

=head1 AUTHOR

Eric Estabrooks, estabroo@ispn.com

=head1 SEE ALSO

perl(1).

=cut
