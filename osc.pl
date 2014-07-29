#!/usr/bin/perl
use Getopt::Long;
use File::Basename;
use JSON;
use strict;

###############################
# Author: wenfeng@cn.ibm.com  #                                                                                    #
###############################

my %ip_map = (
	'10.66.187.137' => 'keystone',
	'10.66.187.138' => 'network',
	'10.66.187.139' => 'dashboard',
	'10.66.187.140' => 'nova_api',
	'10.66.187.141' => 'nova_conductor',
	'10.66.187.142' => 'nova_scheduler',
	'10.66.187.143' => 'glance_api',
	'10.66.187.144' => 'glance_registry',
	'10.66.187.145' => 'neutron_server',
	'10.66.187.146' => 'db',
	'10.66.187.147' => 'nova_novncproxy',
	'10.66.187.148' => 'nova_consoleauth',
	'10.66.187.149' => 'qpid',
	'10.66.187.133' => 'haproxy',
	'10.66.112.228' => 'compute',
	'10.66.187.134' => 'client'
);
my %port_map = (
	'3000' => 'keystone-5000',
	'3001' => 'glance_registry-9191',
	'3002' => 'glance_api-9292',
	'3004' => 'nova_api-8774',
	'3005' => 'nova_api-8775',
	'3006' => 'neutron_server-9696',
	'3007' => 'keystone-35357',
	'3008' => 'nova_novncproxy-6080',
	'5672' => 'qpid-5672'
);

sub is_request {
	my $to = shift;
	my $port = ( split /\./, $to )[-1];

	for my $p ( keys %port_map ) {
		if ( $p eq $port ) {
			return 1;
		}
	}
	return 0;
}

sub format_json {
	my $input = shift;
	my ( $head, $tail );
	my $json_text;
	if ( $input =~ /(oslo\.message.{3})(\{.*\})/ ) {
		$head      = "$`$1";
		$json_text = $2;
		my $perl_scalar = from_json( $json_text, { utf8 => 1 } );
		$json_text = to_json( $perl_scalar, { ascii => 1, pretty => 1 } );
		$input = "$head\n$json_text\n";
		return $input;
	} elsif ( $input =~ /\bHTTP\b/ ) {
		if ( $input =~ /(\{.*\})/ ) {
			$head      = $`;
			$json_text = $1;
			my $perl_scalar = from_json( $json_text, { utf8 => 1 } );
			$json_text = to_json( $perl_scalar, { ascii => 1, pretty => 1 } );
			$input = "$head\n$json_text\n";
		}
		return $input;
	}
	return '';
}

sub translate_ipport {
	my $ipport = shift;
	my @tmp    = split /\./, $ipport;
	my $port   = pop @tmp;
	my $ip     = join '.', @tmp;
	$ip   = $ip_map{$ip}     if ( $ip_map{$ip} );
	$port = $port_map{$port} if ( $port_map{$port} );
	if ( $port =~ /^\d+$/ ) {
		return $ip;
	}
	$port =~ s/-\d+$//;
	return $port;
}

sub format_pkgs {
	my $pkgs = shift;
	for my $pkg (@$pkgs) {
		$pkg->{'is_request'} = is_request( $pkg->{'to'} );
		$pkg->{'FROM'}       = translate_ipport( $pkg->{'from'} );
		$pkg->{'TO'}         = translate_ipport( $pkg->{'to'} );
		$pkg->{'content'}    = format_json( $pkg->{'content'} );
		my @lines = split /\n/, $pkg->{'content'};
		if ( !$pkg->{'msg_type'} ) {
			for my $line (@lines) {
				if ( $line =~ /HTTP\/1\.1/ ) {
					$pkg->{'msg_type'} = 'REST';
					my $l = $line;
					$l =~ s/\s*HTTP\/1\.1\s*//;
					$l =~ s/([=\/\?][a-zA-Z0-9\-]{16})[a-zA-Z0-9\-]{12,}/$1/g;
					$pkg->{'summary'} = $l;
					last;
				} elsif ( $line =~ /oslo\.message/ ) {
					$pkg->{'msg_type'} = 'RPC';
					last;
				}
			}
		}
		if ( $pkg->{'msg_type'} eq 'RPC' ) {
			for my $line (@lines) {
				if ( $line =~ /"_unique_id"\s*:\s*"(\S+)"/ ) {
					$pkg->{'unique_id'} = $1;
				} elsif ( $line =~ /"method"\s*:\s*"(\S+)"/ ) {
					$pkg->{'method'} = $1;
				} elsif ( $line =~ /"_reply_q"\s*:\s*"(\S+)"/ ) {
					$pkg->{'reply_q'} = $1;
				} elsif ( $line =~ /&(reply_\S{32})/ ) {
					$pkg->{'reply_q0'} = $1;
				}
				last
				  if (  $pkg->{'unique_id'}
					and $pkg->{'method'}
					and ( $pkg->{'reply_q'} or $pkg->{'reply_q0'} ) );
			}
		}
	}
	return $pkgs;
}

sub load_pkgs {
	my $file     = shift;
	my $content  = `cat $file`;
	my @lines    = split /\n/, $content;
	my @packages = ();
	for my $line (@lines) {
		if ( $line =~ /(\d+):(\d+):(\d+)\.(\d+)\s+IP (\S+) > (\S+): Flags.*seq (\d+):(\d+).*length (\d+)/ ) {
			my ( $hour, $min, $sec, $micro, $from, $to, $start, $end, $length ) = ( $1, $2, $3, $4, $5, $6, $7, $8, $9 );
			my $pkg;
			$pkg->{'from'}    = $from;
			$pkg->{'to'}      = $to;
			$pkg->{'length'}  = $length;
			$pkg->{'content'} = '';
			$pkg->{'hour'}    = $hour;
			$pkg->{'min'}     = $min;
			$pkg->{'sec'}     = $sec;
			$pkg->{'micro'}   = $micro;

			$pkg->{'timestamp'} = int ( ( $hour * 60 * 60 + $min * 60 + $sec ) * 1000 + $micro / 1000);
			if (@packages) {
				my $p = $packages[-1];
				$p->{'content'} = substr( $p->{'content'}, 0 - $p->{'length'} );
			}
			push @packages, $pkg;
		} else {
			next if ( !@packages );
			my $pkg = $packages[-1];
			if ( $pkg->{'content'} ) {
				$pkg->{'content'} = "$pkg->{'content'}\n$line";
			} else {
				$pkg->{'content'} = $line;
			}
		}
	}
	if (@packages) {
		my $p = $packages[-1];
		$p->{'content'} = substr( $p->{'content'}, 0 - $p->{'length'} );
	}
	return \@packages;
}

sub merge_pkgs {
	my $pkgs   = shift;
	my @merged = ();
	for ( my $i = 0 ; $i <= $#$pkgs ; $i++ ) {
		my $p = $pkgs->[$i];
		next if ( $p->{'merged'} );
		my $completed = 0;
		for ( my $j = $i + 1 ; $j <= $#$pkgs ; $j++ ) {
			my $n = $pkgs->[$j];
			if ( $n->{'from'} eq $p->{'from'} and $n->{'to'} eq $p->{'to'} ) {
				if ( $n->{'content'} !~ /oslo\.message/ ) {
					$p->{'content'} .= $n->{'content'};
					$n->{'merged'} = 1;
				} else {
					$completed = 1;
					push @merged, $p;
					last;
				}
			} elsif ( $n->{'from'} eq $p->{'to'}
				and $n->{'to'} eq $p->{'from'} )
			{
				$n->{'cost'} = $n->{'timestamp'} - $p->{'timestamp'};
				$completed = 1;
				push @merged, $p;
				last;
			}
		}
		if ( !$completed ) {
			push @merged, $p;
		}
	}
	return \@merged;
}

sub skip_pkgs {
	my $pkgs = shift;
	for ( my $i = 0 ; $i <= $#$pkgs ; $i++ ) {
		my $pkg = $pkgs->[$i];
		$pkg->{'skipped'} = 1 if ( !$pkg->{'content'} );

		#$pkg->{'skipped'} = 1 if ( $pkg->{'FROM'} eq 'keystone' or $pkg->{'TO'} eq 'keystone' );
		if ( $pkg->{'msg_type'} eq 'RPC' and !$pkg->{'is_request'} ) {
			for ( my $j = 0 ; $j < $i ; $j++ ) {
				my $p = $pkgs->[$j];
				if ( $p->{'msg_type'} eq 'RPC' and $p->{'is_request'} ) {
					if ( $pkg->{'unique_id'} eq $p->{'unique_id'} ) {
						$pkg->{'from'}       = $p->{'from'};
						$pkg->{'FROM'}       = $p->{'FROM'};
						$pkg->{'is_request'} = 1;
						if ( $pkg->{'reply_q0'} ) {
							$pkg->{'is_request'} = 0;
						}
						$pkg->{'consumed'} = 1;
						if ( $p->{'skipped'} ) {
							$pkg->{'consumed'} += 1;    #?
						} else {
							$p->{'skipped'} = 1;
						}
						last;
					}
				}
			}
		}
	}
	my @merged = grep { !$_->{'skipped'} } @$pkgs;
	for ( my $i = 0 ; $i <= $#merged ; $i++ ) {
		my $req_pkg = $merged[$i];
		if (    $req_pkg->{'msg_type'} eq 'RPC'
			and $req_pkg->{'method'}
			and $req_pkg->{'is_request'} )
		{
			my $timestamp = $req_pkg->{'timestamp'};
			for ( my $j = $i + 1 ; $j <= $#merged ; $j++ ) {
				my $rsp_pkg = $merged[$j];
				if (    $rsp_pkg->{'msg_type'} eq 'RPC'
					and !$rsp_pkg->{'is_request'}
					and $req_pkg->{'reply_q'} eq $rsp_pkg->{'reply_q0'} )
				{
					$rsp_pkg->{'cost'} =
					  int( $rsp_pkg->{'timestamp'} - $timestamp );
					$timestamp = $rsp_pkg->{'timestamp'};
				}
			}
		}
	}
	return \@merged;
}

sub print_pkgs {
	my ( $pkgs, $basename ) = @_;
	open F1, '>', "$basename.txt"     or die $!;
	open F2, '>', "$basename-all.txt" or die $!;
	for my $p (@$pkgs) {
		my $from = $p->{'FROM'};
		my $to   = $p->{'TO'};
		my $cost = $p->{'cost'};
		$cost = " [$cost]" if ($cost);
		if ( $p->{'msg_type'} eq 'REST' ) {
			my $summary = $p->{'summary'};
			$summary =~ s/\?/\?\\n/g if ( length $summary > 30 );
			$summary =~ s/&/&\\n/g   if ( length $summary > 30 );
			if ( $p->{'is_request'} ) {
				print F1 "$from->$to:$summary\n";
			} else {
				print F1 "$from-->$to:$summary$cost\n";
			}
		} else {
			my $id     = $p->{'unique_id'};
			my $method = $p->{'method'};
			my $cast   = '';
			$cast = '*' if ( !$p->{'reply_q'} );
			$id =~ s/(.{16}).*/$1/;
			$method ||= $id;
			if ( $p->{'consumed'} == 1 ) {
				if ( $p->{'is_request'} ) {
					print F1"$from->$to:$cast\RPC $method\n";
				} else {
					print F1 "$from-->$to:RPC $method$cost\n";
				}
			} elsif ( $p->{'consumed'} > 1 ) {
				if ( $p->{'is_request'} ) {
					print F1 "$from->$to:== $cast\RPC $method\n";
				} else {
					print F1 "$from-->$to:== RPC $method$cost\n";
				}
			}
		}

		print F2 "###$p->{'hour'}:$p->{'min'}:$p->{'sec'}.$p->{'micro'} From $from to $to $p->{'msg_type'}\n";
		print F2 "$p->{'content'}\n";
	}
	close F1;
	close F2;
}

sub main {
	my $dumpfile;
	GetOptions( "f=s" => \$dumpfile );
	die "$dumpfile is not a correct tcpdump file\n" if ( !-f $dumpfile );
	my $basename = basename($dumpfile);
	my $pkgs     = load_pkgs($dumpfile);
	$pkgs = merge_pkgs($pkgs);
	$pkgs = format_pkgs($pkgs);
	$pkgs = skip_pkgs($pkgs);
	print_pkgs( $pkgs, $basename );
}
main();
