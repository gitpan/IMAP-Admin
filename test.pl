# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..1\n"; }
END {print "not ok 1\n" unless $loaded;}
use IMAP::Admin;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$testuser = "user.testjoebob";

print "Please enter the server and the admin user and password at the prompts\n";
print "Enter server: ";
chomp($server = <>);
$port = 143;
print "Enter login: ";
chomp($login = <>);
system "stty -echo";
print "Enter password: ";
chomp($password = <>);
print "\n";
system "stty echo";

$imap = IMAP::Admin->new('Server' => $server, 'Port' => $port,
			 'Login' => $login, 'Password' => $password);
for ($err = $imap->create($testuser); $err != 0; 
     $err = $imap->create($testuser)) {
	print <<EOF;
The user I was testing with ($testuser) already exists.
Please enter a email user that does not exist on $server.
EOF
	print "username: ";
	chomp($testuser = <>); 
}
print "ok 2\n";
undef @list;
@list = $imap->list($testuser);
if (defined(@list)) {
	print "ok 3: found [@list]\n";
} else {
	print "not ok 3: $imap->{'Error'}\n";
}
if ($imap->{'Capability'} =~ /ACL/) {
	print "pre4: IMAP server supports ACL, setting delete permission\n";
	$err = $imap->set_acl($testuser, $login, "d");
	if ($err == 0) {
		print "ok pre4\n";
	} else {
		print "not ok pre4: $imap->{'Error'}\n";
	}
} else {
	print "pre4: IMAP server doesn't support ACL, trying delete directly\n";
}
$err = $imap->delete($testuser);
if ($err == 0) {
	print "ok 4\n";
} else {
	print "not ok 4\n";
}
$err = $imap->create($testuser, "default");
if ($err == 0) {
	print "ok 5 : test user created with optional partition set to default\n";
	if ($imap->{'Capability'} =~ /ACL/) {
		print "pre6: IMAP server supports ACL, setting delete permission\n";
		$err = $imap->set_acl($testuser, $login, "d");
		if ($err == 0) {
			print "ok pre6\n";
		} else {
			print "not ok pre6: $imap->{'Error'}\n";
		}
	} else {
		print "pre6: IMAP server doesn't support ACL, trying delete directly\n";
	}
} else {
	print "not ok 5: test user with optional partition argument failed, this might not be a problem\n";
}

$subf = $testuser.".sub folder";
$err = $imap->create('"'.$subf.'"');
if ($err == 0) {
	print "ok 6 : created sub folder (sub folder) for $testuser\n";
} else {
	print "not ok 6 : $imap->{'Error'}\n";
}

$what = $testuser.'.*';
undef @list;
@list = $imap->list($what);
if (!defined(@list)) {
	print "not ok 7 : sub folder wasn't really created\n";
} else {
	if ($list[0] eq $subf) {
		print "ok 7\n";
	} else {
		print "not ok 7 : something was created (in 6) but didn't get reported correctly [@list]\n";
	}
}
$err = $imap->delete($testuser);
if ($err == 0) {
	print "ok 8\n";
} else {
	print "not ok 8, but if 5 failed this will fail as well -- $imap->{'Error'}\n";
}
undef @list;
@list = $imap->list($testuser);
if (!defined(@list)) {
	print "ok 9: $imap->{'Error'}\n";
} else {
	print "not ok 9: found [@list]\n";
}
$imap->close;
