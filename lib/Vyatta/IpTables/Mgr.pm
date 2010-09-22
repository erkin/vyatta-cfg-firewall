#
# Module: Vyatta::IpTables::Mgr.pm
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: June 2010
# Description: common iptables routines
# 
# **** End License ****
#

package Vyatta::IpTables::Mgr;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(ipt_find_chain_rule ipt_enable_conntrack
                 ipt_disable_conntrack count_iptables_rules);


sub ipt_find_chain_rule {
  my ($iptables_cmd, $table, $chain, $search) = @_;
  
  my ($num, $chain2) = (undef, undef);
  my $cmd = "$iptables_cmd -t $table -L $chain -vn --line";
  my @lines = `$cmd 2> /dev/null | egrep ^[0-9]`;
  if (scalar(@lines) < 1) {
    return;
  }
  foreach my $line (@lines) {
    ($num, undef, undef, $chain2) = split /\s+/, $line;
    last if $chain2 eq $search;
    ($num, $chain2) = (undef, undef);
  }

  return $num if defined $num;
  return;
}

my %conntrack_hook_hash = 
   ('PREROUTING' => 'VYATTA_CT_PREROUTING_HOOK',
    'OUTPUT'     => 'VYATTA_CT_OUTPUT_HOOK',
   );

sub ipt_enable_conntrack {
    my ($iptables_cmd, $chain) = @_;

    system("$iptables_cmd -t raw -L $chain -n >& /dev/null");
    
    if ($? >> 8) {
	# chain does not exist yet. set up conntrack.
	system("$iptables_cmd -t raw -N $chain");
	system("$iptables_cmd -t raw -A $chain -j ACCEPT");
        
        foreach my $label ('PREROUTING', 'OUTPUT') {
            my $index;
            my $conntrack_hook = $conntrack_hook_hash{$label};
            $index = ipt_find_chain_rule($iptables_cmd, 'raw',
                                         $label, $conntrack_hook);
            if (! defined($index)) {
                print "Error: unable to find [$label] [$conntrack_hook]\n";
                return 1;
            }
            $index++;
            system("$iptables_cmd -t raw -I $label $index -j $chain");
        }
    }
    return 0;
}

sub ipt_disable_conntrack {
    my ($iptables_cmd, $chain) = @_;

    my @lines;
    foreach my $label ('PREROUTING', 'OUTPUT') {
        my $index;
        my $conntrack_hook = $conntrack_hook_hash{$label};
        $index = ipt_find_chain_rule($iptables_cmd, 'raw',
                                     $label, $chain);
        if (! defined($index)) {
            print "Error: ipt_disable_conntrack failed to find "
                  . "[$label][$chain]\n";
            return 1;
        }
        system("$iptables_cmd -t raw -D $label $index");
    }
    
    system("$iptables_cmd -t raw -F $chain >& /dev/null");
    system("$iptables_cmd -t raw -X $chain >& /dev/null");
    return 0;
}

sub count_iptables_rules {
    my ($command, $table, $chain) = @_;
    my @lines = `sudo $command -t $table -L $chain -n --line`;
    my $cnt = 0;
    foreach my $line (@lines) {
      $cnt++ if $line =~ /^\d/;
    }
    return $cnt;
}

1;
