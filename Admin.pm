# $Id: Admin.pm,v 1.19 2000/06/22 13:05:02 eric Exp $

package IMAP::Admin;

use strict;
use Carp;
use IO::Select;
use IO::Socket;
use Text::ParseWords qw(quotewords);

use vars qw($VERSION);

$VERSION = '1.2.5';

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
    my $try = <$fh>; # get Banner
    if ($try !~ /\* OK/) {
	$self->close;
	print "try = [$try]\n";
	croak "$self->{'CLASS'}: Connection to $self->{'Server'} bad/no response: $!";
    }
    print $fh "try CAPABILITY\n";
    chomp ($try = <$fh>);
    if ($try =~ /\r$/) {
	chop($try);
    }
    $self->{'Capability'} = $try;
    $try = <$fh>;
    if ($try !~ /^try OK/) {
	croak "$self->{'CLASS'}: Couldn't do capabilites check";
    }
    print $fh qq{try LOGIN "$self->{'Login'}" "$self->{'Password'}"\n};
    $try = <$fh>;
    if ($try =~ /Login incorrect/) {
	$self->close;
	croak "$self->{'CLASS'}: Login incorrect while connecting to $self->{'Server'}";
    } elsif ($try =~ /^try OK/) {
	return;
    } else {
	croak "$self->{'CLASS'}: Unknown error -- $try";
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
    my $try = <$fh>;
    close($self->{'Socket'});
    delete $self->{'Socket'};
}

sub create {
    my $self = shift;

    if ((scalar(@_) != 1) && (scalar(@_) != 2)) {
	$self->_error("create", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("create", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    if (scalar(@_) == 1) { # a partition exists
	print $fh qq{try CREATE "$mailbox" $_[0]\n};
    } else {
	print $fh qq{try CREATE "$mailbox"\n};
    }
    my $try = <$fh>;
    if ($try =~ /^try OK/) {
	$self->{'Error'} = 'No Errors';
	return 0;
    } else {
	$self->_error("create", "couldn't create", $mailbox, ":", $try);
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
    print $fh qq{try DELETE "$mailbox"\n};
    my $try = <$fh>;
    if ($try =~ /^try OK/) {
	$self->{'Error'} = 'No Errors';
	return 0;
    } else {
	$self->_error("delete", "couldn't delete", $mailbox, ":", $try);
	return 1;
    }
}
sub get_quotaroot { # returns an array or undef
    my $self = shift;
    my (@quota, @info);

    if (!($self->{'Capability'} =~ /QUOTA/)) {
	$self->_error("get_quotaroot", "QUOTA not listed in server's capabilities");
	return 1;
    }
    if (scalar(@_) != 1) {
	$self->_error("get_quotaroot", "incorrect number of arguments");
	return 1;
    }
    my $mailbox = shift;
    if (!defined($self->{'Socket'})) {
	$self->_error("get_quotaroot", "no connection open to", $self->{'Server'});
	return 1;
    }
    my $fh = $self->{'Socket'};
    print $fh qq{try GETQUOTAROOT "$mailbox"\n};
    my $try = <$fh>;
    while ($try =~ /[\r\n]$/) {
      chop($try);
    }
    while ($try = /^\* QUOTA/) {
	$try =~ tr/\)\(//d;
	@info = (split(' ', $try))[2,4,5];
	push @quota, @info;
	$try = <$fh>;
        while ($try =~ /[\r\n]$/) {
          chop($try);
        }
    }
    if ($try =~ /^try OK/) {
	return @quota;
    } else {
	$self->_error("get_quotaroot", "couldn't get quota for", $mailbox, ":", $try);
	return;
    }
}

sub get_quota { # returns an array or undef
    my $self = shift;
    my (@quota, @info);

    if (!($self->{'Capability'} =~ /QUOTA/)) {
	$self->_error("get_quota", "QUOTA not listed in server's capabilities");
	return 1;
    }
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
    print $fh qq{try GETQUOTA "$mailbox"\n};
    my $try = <$fh>;
    while ($try =~ /[\r\n]$/) {
      chop($try);
    }
    while ($try =~ /^\* QUOTA/) {
	$try =~ tr/\)\(//d;
	@info = (split(' ',$try))[2,4,5];
	push @quota, @info;
	$try = <$fh>;
        while ($try =~ /[\r\n]$/) {
          chop($try);
        }
    }
    if ($try =~ /^try OK/) {
	return @quota;
    } else {
	$self->_error("get_quota", "couldn't get quota for", $mailbox, ":", $try);
	return;
    }
}

sub set_quota {
    my $self = shift;

    if (!($self->{'Capability'} =~ /QUOTA/)) {
	$self->_error("set_quota", "QUOTA not listed in server's capabilities");
	return 1;
    }
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
    if ($quota eq "none") {
	print $fh qq{try SETQUOTA "$mailbox" ()\n};
    } else {
	print $fh qq{try SETQUOTA "$mailbox" (STORAGE $quota)\n};
    }
    my $try = <$fh>;
    if ($try =~ /^try OK/) {
	$self->{'Error'} = "No Errors";
	return 0;
    } else {
	$self->_error("set_quota", "couldn't set quota for", $mailbox, ":", $try);
	return 1;
    }
}

sub get_acl { # returns an array or undef
    my $self = shift;
    my (@info, @acl_item, @acl, $item);

    if (!($self->{'Capability'} =~ /ACL/)) {
	$self->_error("get_acl", "ACL not listed in server's capabilities");
	return 1;
    }
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
    print $fh qq{try GETACL "$mailbox"\n};
    my $try = <$fh>;
    while ($try =~ /[\r\n]$/) {
	chop($try);
    }
    while ($try =~ /^\* ACL/) {
	@info = split(' ',$try,4);
        @acl_item = split(' ',$info[3]);
	push @acl, @acl_item;
	$try = <$fh>;
        while ($try =~ /[\r\n]$/) {
	    chop($try);
        }
    }
    if ($try =~ /^try OK/) {
	return @acl;
    } else {
	$self->_error("get_acl", "couldn't get acl for", $mailbox, ":", $try);
	return;
    }
}

sub set_acl {
    my $self = shift;
    my ($id, $acl);

    if (!($self->{'Capability'} =~ /ACL/)) {
	$self->_error("set_acl", "ACL not listed in server's capabilities");
	return 1;
    }
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
	print $fh qq{try SETACL "$mailbox" "$id" "$acl"\n};
	my $try = <$fh>;
	if ($try !~ /^try OK/) {
	    $self->_error("set_acl", "couldn't set acl for", $mailbox, $id, 
			 $acl, ":", $try);
	    return 1;
	}
    }
    $self->{'Error'} = 'No Errors';
    return 0;
}

sub delete_acl {
    my $self = shift;
    my ($id, $acl);

    if (!($self->{'Capability'} =~ /ACL/)) {
	$self->_error("delete_acl", "ACL not listed in server's capabilities");
	return 1;
    }
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
	print $fh qq{try DELETEACL "$mailbox" "$id"\n};
	my $try = <$fh>;
	if ($try !~ /^try OK/) {
	    $self->_error("delete_acl", "couldn't delete acl for", $mailbox,
			  $id, $acl, ":", $try);
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
    print $fh qq{try LIST "" "$list"\n};
    my $try = <$fh>;
    while ($try =~ /[\r\n]$/) {
      chop($try);
    }
    while ($try =~ /\* /) { # danger danger (could lock up needs timeout)
	@info = quotewords('\s+', 0, $try);
	push @mail, $info[$#info];
	$try = <$fh>;
        while ($try =~ /[\r\n]$/) {
          chop($try);
        }
    }
    if ($try =~ /^try OK/) {
	return @mail;
    } else {
	$self->_error("list", "couldn't get list for", $list, ":", $try);
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
  $err = $imap->create("user.bob", "green"); 
  $err = $imap->delete("user.bob");

  @quota = $imap->get_quotaroot("user.bob");
  @quota = $imap->get_quota("user.bob");
  $err = $imap->set_quota("user.bob", 10000);

  @acl = $imap->get_acl("user.bob");
  $err = $imap->set_acl("user.bob", "admin", "lrswipdca", "joe", "lrs");
  $err = $imap->delete_acl("user.bob", "joe", "admin");
 
  @list = $imap->list("user.bob");
  @list = $imap->list("user.b*");

  $imap->{'Capability'} # this contains the Capabilities reply from the IMAP server

  $imap->close; # close open imap connection

=head1 DESCRIPTION

IMAP::Admin provides basic IMAP server adminstration.  It provides functions for creating and deleting mailboxes and setting various information such as quotas and access rights.

It's interface should, in theory, work with any RFC compliant IMAP server, but I currently have only tested it against Carnegie Mellon University's Cyrus IMAP and Mirapoint's IMAP servers.  It does a CAPABILITY check for specific extensions to see if they are supported.

Operationally it opens a socket connection to the IMAP server and logs in with the supplied login and password.  You then can call any of the functions to perform their associated operation.


=head2 MAILBOX FUNCTIONS

RFC2060 commands.  These should work with any RFC2060 compliant IMAP mail servers.

create makes new mailboxes.  Cyrus IMAP, for normal mailboxes, has the user. prefix.
create returns a 0 on success or a 1 on failure.  An error message is placed in the object->{'Error'} variable on failure. create takes an optional second argument that is the partition to create the mailbox in (I don't know if partition is rfc or not, but it is supported by Cyrus IMAP and Mirapoint).

delete destroys mailboxes.
delete returns a 0 on success or a 1 on failure.  An error message is placed in the object->{'Error'} variable on failure.

list lists mailboxes.  list accepts wildcard matching


=head2 QUOTA FUNCTIONS

NOT RFC2060 commands.  These are supported by Cyrus IMAP and Mirapoint.

get_quotaroot and get_quota retrieve quota information.  They return an array on success and undef on failure.  In the event of a failure the error is place in the object->{'Error'} variable.  The array has three elements for each item in the quota. 
$quota[0] <- mailbox name
$quota[1] <- quota amount used in kbytes
$quota[2] <- quota in kbytes

set_quota sets the quota.  The number is in kilobytes so 10000 is approximately 10Meg.
set_quota returns a 0 on success or a 1 on failure.  An error message is placed in the object->{'Error'} variable on failure.

To delete a quota do a set_quota($mailbox, "none");


=head2 ACCESS CONTROL FUNCTIONS

NOT RFC2060 commands.  These are supported by Cyrus IMAP and Mirapoint.

get_acl retrieves acl information.  It returns an array on success and under on failure.  In the event of a failure the error is placed in the object->{'Error'} variable. The array contains a pair for each person who has an acl on this mailbox
$acl[0] user who has acl information
$acl[1] acl information
$acl[2] next user ...

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

=head1 LICENSE

This is licensed under the Artistic license (same as perl).  A copy of the license is included in this package.  The file is called Artistic.  If you use this in a product or distribution drop me a line, 'cause I am always curious about that...

=head1 CVS REVISION

$Id: Admin.pm,v 1.19 2000/06/22 13:05:02 eric Exp $

=head1 AUTHOR

Eric Estabrooks, eric@urbanrage.com

=head1 SEE ALSO

perl(1).

=cut
