###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - der.einstein      Initiator and Commiter
#       - viegener          Thanks for many Commits
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
##
## - initial HTTPUtils modification
## - do setters
## - add queuing
## - work off queue from callback
## 0.0.27
## - RequestAccess status as reading --> access - accepted
## - removed LoeweTV_ResponseProcessing
## 0.0.28
## - framework to collect data from XML in hash for readings update
## - change mac, chassis,version as reading
## - sendRequest: rename RCkey to a generic param 
## - sendRequest: allow additional param (also as array)
## - add getter
## - add get volume and volume reading
## - add get mutea and mute reading
## 0.0.29

## - lists start with 0 (start index)
## - first tests with channellist / mediatiem
## - added channellist listofchannellist media item but without result eval
## 0.0.30

## 0.0.31
  
## - clean some old code
## - honor attribute channellist for get channellist 
## - grab channel and automatically extend list and queue getmediatiems
## 0.0.32
  
##
###############################################################################
###############################################################################
##  TODO
###############################################################################
## - 
## - store mediaitem information 
## - 
## - 
## - grab channel list of lists 
## - 
## - handle soap failures
##    <SOAP-ENV:Body>  <SOAP-ENV:Fault>   <faultcode>Server</faultcode>   <faultstring>URN 'urn:loewe.de:RemoteTV:Tablet' not found</faultstring>   
##  <faultactor>cSOAP_Server</faultactor>   <detail/>  </SOAP-ENV:Fault> </SOAP-ENV:Body></SOAP-ENV:Envelope>
##
## - 
## - check channels
## - 
## - regularly get volume / mute
## - activate timerstatusrequest
## - start/stop presence and timerstatusrequest on disabled
## - 
## - calc fcid from uniqueid?
## - update state consistently?
##
## - change log level for logs
###############################################################################




package main;

use strict;
use warnings;

use Data::Dumper::Simple;    # Kann später entfernt werden, nur zum Debuggen


my $missingModul = "";
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use HTTP::Request::Common;1" or $missingModul .= "HTTP::Request::Common ";
eval "use XML::Twig;1" or $missingModul .= "XML::Twig ";

use Blocking;


my $version = "0.0.32";


# Declare functions
sub LoeweTV_Define($$);
sub LoeweTV_Undef($$);
sub LoeweTV_Initialize($);
sub LoeweTV_Set($@);
sub LoeweTV_Get($@);
sub LoeweTV_WakeUp_Udp($@);
sub LoeweTV_SendRequest($$;$$$);
sub LoeweTV_Presence($);
sub LoeweTV_PresenceRun($);
sub LoeweTV_PresenceDone($);
sub LoeweTV_PresenceAborted($);
sub LoeweTV_TimerStatusRequest($);
sub LoeweTV_Attr(@);
sub LoeweTV_FirstRun($);
sub LoeweTV_IsPresent($);
sub LoeweTV_HasAccess($);
sub LoeweTV_ParseRequestAccess($$);

#########################
# Globals




#########################
# TYPE routines

sub LoeweTV_Initialize($) {
    my ($hash) = @_;
    
    $hash->{GetFn}      = "LoeweTV_Get";
    $hash->{SetFn}      = "LoeweTV_Set";
    $hash->{DefFn}      = "LoeweTV_Define";
    $hash->{UndefFn}    = "LoeweTV_Undef";

    $hash->{AttrList}   =  "fhemMAC " .
                        "interval " .
                        "channellist " .
                        #"ip " .
                        #"tvmac " .
                        #"action " .
                        #"RCkey " .
                        #"clientid " .
                        #"fcid " .
                        "status:Accepted,Pending,Denied,undef " .
                        #"access:accepted,misc " .
                        #"pingresult:down,up " .
                        #"lastersponse " .
                        #"lastchunk " .
                        #"volstate " .
                        #"mutstate:0,1 " .
                        #"curlocator " .
                        #"curevent " .
                        #"nextevent " .
                        $readingFnAttributes;
                         
    foreach my $d(sort keys %{$modules{LoeweTV}{defptr}}) {
    
        my $hash = $modules{LoeweTV}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub LoeweTV_Define($$) {

    my ( $hash, $def )  = @_;
    
    my @a               = split( "[ \t][ \t]*", $def );


    return "too few parameters: define <NAME> LoeweTV <HOST> <MAC-TV>" if( @a < 3 or @a > 4 );
    return "Cannot define Loewe device. Perl modul ${missingModul}is missing." if ( $missingModul );

    
    my $name            = $hash->{NAME};
    my $host            = $a[2];
    
    $hash->{HOST}       = $host;
    $hash->{FCID}       = 1234;
    $hash->{TVMAC}      = $a[3] if(defined($a[3]));
    $hash->{VERSION}    = $version;
    $hash->{INTERVAL}   = 15;
    $hash->{CLIENTID}   = "?";
    
    
    Log3 $name, 3, "LoeweTV $name: defined LoeweTV device";
    
    $modules{LoeweTV}{defptr}{HOST} = $hash;
    readingsSingleUpdate($hash,'state','initialized',1);
    
    if( $init_done ) {
        LoeweTV_Presence($hash);
        InternalTimer( gettimeofday()+5, "LoeweTV_FirstRun", $hash, 0 );
    } else {
        InternalTimer( gettimeofday()+15, "LoeweTV_Presence", $hash, 0 );
        InternalTimer( gettimeofday()+20, "LoeweTV_FirstRun", $hash, 0 );
    }
    
    return undef;
}

sub LoeweTV_Undef($$) {

    my ( $hash, $arg ) = @_;


    #RemoveInternalTimer($hash);
    delete $modules{LoeweTV}{defptr}{HOST} if( defined($modules{LoeweTV}{defptr}{HOST}) );

    return undef;
}

#########################
# Device Instance routines
sub LoeweTV_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            $hash->{PARTIAL} = '';
            Log3 $name, 3, "LoeweTV ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LoeweTV ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "LoeweTV ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LoeweTV ($name) - delete disabledForIntervals";
        }
    }
    
    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            $hash->{INTERVAL}   = $attrVal;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "LoeweTV ($name) - set interval: $attrVal";
            LoeweTV_TimerStatusRequest($hash);
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL}   = 15;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "LoeweTV ($name) - delete User interval and set default: 300";
            LoeweTV_TimerStatusRequest($hash);
        }
        
    }

    return undef;
}

sub LoeweTV_FirstRun($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    if(LoeweTV_IsPresent( $hash )) {
        LoeweTV_SendRequest($hash,'GetDeviceData');
    } else {
        readingsSingleUpdate($hash,'state','off',1);
    }
    
    InternalTimer( gettimeofday()+10, "LoeweTV_TimerStatusRequest", $hash, 1 );
}

sub LoeweTV_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    
    my ($action,$actPar1, $actPar2);

    my @actionargs;
    
    if( lc $cmd eq 'setactionfield' ) {

    } elsif( lc $cmd eq 'volume' ) {
        return "$cmd needs volume" if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^\d+$/ ) );
        # value range is between 0 - 999999
        @actionargs = ( 'SetVolume', $args[0] );    
    
    } elsif( lc $cmd eq 'mute' ) {
        return "$cmd needs argument on or off " if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^(on|off)$/ ) );
        @actionargs = ( 'SetMute', ( $args[0] eq "on" )?1:0 );    
        
    } elsif( lc $cmd eq 'wakeup' ) {
    
        LoeweTV_WakeUp_Udp($hash,$hash->{TVMAC},$hash->{HOST});
        return;
    
    } elsif( lc $cmd eq 'remotekey' ) {
        return "$cmd needs argument remote key" if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^\d+$/ ) );
        @actionargs = ( 'InjectRCKey', $args[0] );    
    
    } elsif( lc $cmd eq 'access' ) {
        @actionargs = ( 'RequestAccess');    
    } elsif( lc $cmd eq 'devicedata' ) {
        @actionargs = ( 'GetDeviceData');    
   
    } elsif( lc $cmd eq '' ) {
    
    
    } else {
    
        my $list    = 'SetActionField volume:slider,0,1,100 RemoteKey mute:on,off WakeUp:noArg access:noArg deviceData:noArg ';
        
        return "Unknown argument $cmd, choose one of $list";
    }

    
    if ( scalar(@actionargs) > 0 ) {
      # 
      return "LoeweTV $name is not present" if( ! LoeweTV_IsPresent( $hash ));
      LoeweTV_SendRequest($hash,$actionargs[0],$actionargs[1],$actionargs[2]);
    }
    
    Log3 $name, 2, "LoeweTV $name: called function LoeweTV_Set()";
    return undef;
}

sub LoeweTV_Get($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    
    my ($action,$actPar1, $actPar2);

    my @actionargs;
    
    if( lc $cmd eq 'volume' ) {
        # value range is between 0 - 999999
        @actionargs = ( 'GetVolume' );    
    
    } elsif( lc $cmd eq 'mute' ) {
        @actionargs = ( 'GetMute' );    

    } elsif( lc $cmd eq 'currentplayback' ) {
        @actionargs = ( 'GetCurrentPlayback' );    
        
    } elsif( lc $cmd eq 'listofchannellists' ) {
        $args[0] = 0 if ( ( scalar( @args ) < 1 ) || ( $args[0] !~ /^\d+$/ ) );
        @actionargs = ( 'GetListOfChannelLists', $args[0] );    
        
    } elsif( lc $cmd eq 'channellist' ) {
        $args[0] = AttrVal($name,"channellist","default") if ( ( scalar( @args ) < 1 ) );
        $args[1] = 0 if ( ( scalar( @args ) < 2 ) || ( $args[1] !~ /^\d+$/ ) );
        @actionargs = ( 'GetChannelList', $args[0], $args[1] );    
        
    } elsif( lc $cmd eq 'mediaitem' ) {
        return "$cmd needs a uuid of a media item" if ( scalar( @args ) != 1 );
        @actionargs = ( 'GetMediaItem', $args[0] );    
        
        
    } else {
    
        my $list    = 'volume:noArg mute:noArg currentplayback:noArg listofchannellists channellist mediaitem';
        
        return "Unknown argument $cmd, choose one of $list";
    }

    
    if ( scalar(@actionargs) > 0 ) {
      # 
      return "LoeweTV $name is not present" if( ! LoeweTV_IsPresent( $hash ));
      LoeweTV_SendRequest($hash,$actionargs[0],$actionargs[1],$actionargs[2]);
    }
    
    Log3 $name, 2, "LoeweTV $name: called function LoeweTV_Get()";
    return undef;
}

sub LoeweTV_TimerStatusRequest($) {

### Hier kommen dann die Sachen rein welche alle x Sekunden ausfegührt werden um Infos zu erhalten
### presence zum Beispiel

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    if(LoeweTV_IsPresent( $hash )) {
#???        LoeweTV_SendRequest($hash,'GetDeviceData');
      
    } else {
        readingsSingleUpdate($hash,'state','off',1);
    }
 
    if ( $hash->{INTERVAL} > 0 ) {
      InternalTimer( gettimeofday()+$hash->{INTERVAL}, "LoeweTV_TimerStatusRequest", $hash, 1 );
    }

}

# method to wake via lan, taken from Net::Wake package
sub LoeweTV_WakeUp_Udp($@) {

    my ($hash,$mac_addr,$host,$port) = @_;
    my $name  = $hash->{NAME};

    # use the discard service if $port not passed in
    if (!defined $port || $port !~ /^\d+$/ ) { $port = 9 }

    my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
    if(!$sock) {
        Log3 $name, 3, "LoeweTV ($name) - Can't create WOL socket";
        return 1;
    }
  
    my $ip_addr   = inet_aton($host);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr     =~ s/://g;
    my $packet    = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
    send($sock, $packet, 0, $sock_addr) or die "send : $!";
    close ($sock);

    return 1;
}


sub LoeweTV_ParseRequestAccess($$) {
    
    my ($hash,$access)        = @_;
    
    my $name                    = $hash->{NAME};
 
    return if ( ! defined($access) );
    
    if ( ( lc $access eq "accepted" ) ) {
      readingsSingleUpdate($hash,'state','connected',1);
      readingsSingleUpdate($hash,'access','accepted',1);
    } else {
      Log3 $name, 2, "LoeweTV_ParseRequestAccess $name: not connected";
      readingsSingleUpdate($hash,'access',$access,1);
      readingsSingleUpdate($hash,'state','disconnected',1);
    }
 
} 


# handle channel list
# call GetChannelList with listid
#   on ChannelListView --> get the list id --> remember in hash
#   on ResultItemFragment --> gain attributes --> sequenceNumber="9076679" totalResults="100" returnedResults="100" startIndex="0"
#       if start at 0 --> clean current table
#       if not complete --> queue next trunk startindex+100
#   on ResultItemReference --> queue GetMediaItems for uuid in mediaItemUuid
sub LoeweTV_ChannelList_Reference($$) {
    my ($hash,$reference)  = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 2, "LoeweTV_ChannelList_Reference $name: Reference: ".$reference;
    
    LoeweTV_SendRequest($hash, 'GetMediaItem', $reference );
}

sub LoeweTV_ChannelList_Fragment($$$$$) {
    my ($hash,$sequence,$total,$returned,$start)  = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 2, "LoeweTV_ChannelList_Fragment $name: Sequence: ".$sequence."  Counts: ".$start."-".$returned."  (".$total.")";
    
    my $channelist = $hash->{helper}{ChannelListView};
    
    if ( $start == 0 ) {
      Log3 $name, 2, "LoeweTV_ChannelList_Fragment $name: new list started empty old list";
      # delete current content if content returned
      if ( $returned != 0 ) {
          delete( $hash->{helper}{ChannelList} );
          my %tmp = ();
          $hash->{helper}{ChannelList} = \%tmp;
      }
    } 
    
    
    if ( $returned == 100 ) {
      Log3 $name, 2, "LoeweTV_ChannelList_Fragment $name: queue next request";
      # not yet complete queue the next request
      LoeweTV_SendRequest($hash, 'GetChannelList', $channelist, $start + $returned );
    }
    
}


sub LoeweTV_ChannelList_View($$) {
    my ($hash,$channelist)        = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 2, "LoeweTV_ChannelList_View $name: List: ".$channelist;
    
    $hash->{helper}{ChannelListView} = $channelist;
}




sub LoeweTV_PrepareReading($$$) {
    
    my ($hash,$rname, $rvalue)        = @_;
    
    my $name                    = $hash->{NAME};
 
    my $refreadings = $hash->{HU_SR_PARAMS}->{SR_READINGS};
    
    Log3 $name, 2, "LoeweTV_PrepareReading $name: reading: ".$rname."   value :".$rvalue.":";
    $refreadings->{$rname} = $rvalue;
}
 
# Pars
#   hash
#   action 
#   opt: par1 (RCkey - migt be also representing differnt par)
#   opt: par2 addtl pars
#   opt: retrycount - will be set to 0 if not given (meaning first exec)
sub LoeweTV_SendRequest($$;$$$) {

    my ( $hash, @args) = @_;

    my ( $action, $actPar1, $actPar2, $retryCount) = @args;
    my $name = $hash->{NAME};
  
    my $ret;
  
    Log3 $name, 2, "LoeweTV_SendRequest $name: ";
    
    $retryCount = 0 if ( ! defined( $retryCount ) );
    # increase retrycount for next try
    $args[3] = $retryCount+1;
    
#    my ($message, $response, $request, $userAgent, $noob, $twig2, $content, $handlers);
    my ($message, $request, $content, $handlers);
    our $result ="";
    
    my $actionString = $action.(defined($actPar1)?"  Par1:".$actPar1.":":"")."  ".(defined($actPar2)?"  Par2:".$actPar2.":":"");

    Log3 $name, 2, "LoeweTV_SendRequest $name: called with action ".$actionString;
    
    # ensure actionQueue exists
    $hash->{actionQueue} = [] if ( ! defined( $hash->{actionQueue} ) );

    # Queue if not yet retried and currently waiting
    if ( ( defined( $hash->{doStatus} ) ) && ( $hash->{doStatus} =~ /^WAITING/ ) && (  $retryCount == 0 ) ){
      # add to queue
      Log3 $name, 2, "LoeweTV_SendRequest $name: add action to queue - args: ".$actionString;
      # RequestAccess will always be added to the beginning of the queue
      if ( ( $action eq "RequestAccess" ) || ( $action eq "RequestAccess" ))  {
        unshift( @{ $hash->{actionQueue} }, \@args );
      } else {
        push( @{ $hash->{actionQueue} }, \@args );
      }
      return;
    }  

    #######################
    # check authentication otherwise queue the current cmd and do authenticate first
    if ( ($action ne "RequestAccess") && ( ! LoeweTV_HasAccess($hash) ) ) {
      # add to queue
      Log3 $name, 4, "LoeweTV_SendRequest $name: add action to queue - args ".$actionString;
      push( @{ $hash->{actionQueue} }, \@args );
      
      $action = "RequestAccess";
      $actPar1 = undef;
      $actPar2 = undef;
      # update cmdstring
      $actionString = $action.(defined($actPar1)?"  Par1:".$actPar1.":":"")."  ".(defined($actPar2)?"  Par2:".$actPar2.":":"");
    } 
  
    $hash->{doStatus} = "WAITING";
    $hash->{doStatus} .= " retry $retryCount" if ( $retryCount > 0 );
    
    my %actions = (
        "RequestAccess"         =>  [sub {$content='<ltv:DeviceType>Homeautomation</ltv:DeviceType>
                                        <ltv:DeviceName>FHEM</ltv:DeviceName>
                                        <ltv:DeviceUUID>'.$hash->{TVMAC}.'</ltv:DeviceUUID>
                                        <ltv:RequesterName>FHEM</ltv:RequesterName>'},
                                        {'m:ClientId' => sub {$hash->{CLIENTID} = $_->text_only('m:ClientId')},
                                        'm:AccessStatus' => sub {LoeweTV_ParseRequestAccess($hash, $_->text_only('m:AccessStatus'));},}
                                    ],
                                    
        "InjectRCKey"           =>  [sub {$content='<InputEventSequence>
                                        <RCKeyEvent alphabet="l2700" value="'.$actPar1.'" mode="press"/>
                                        <RCKeyEvent alphabet="l2700" value="'.$actPar1.'" mode="release"/>
                                        </InputEventSequence>'},{"ltv:InjectRCKey" => sub {$hash->{helper}{lastchunk} = $_->text_only();}},],
                                        
        "GetDeviceData"         =>  [sub {$content='';},
                                     {"m:MAC-Address" => sub {LoeweTV_PrepareReading($hash,"TVMAC", $_->text("m:MAC-Address"));},"m:Chassis" => sub {LoeweTV_PrepareReading($hash,"Chassis",$_->text("m:Chassis"));},"m:SW-Version" => sub {LoeweTV_PrepareReading($hash,"SW_Version",$_->text("m:SW-Version"));}}],
            
        "SetVolume"             => [sub {$content="<Value>".($actPar1*10000)."</Value>"},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"volume", int(($_->text ("m:Value")/10000)+0.5));}}
                                    ],
        "GetVolume"             => [sub {$content="";},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"volume", int(($_->text ("m:Value")/10000)+0.5));}}
                                    ],
        "SetMute"             => [sub {$content="<Value>".$actPar1."</Value>"},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"mute", $_->text ("m:Value"));}}
                                    ],
            
        "GetMute"             => [sub {$content=""},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"mute", $_->text ("m:Value"));}}
                                    ],
########## in progress            
        "GetCurrentPlayback"    =>  [sub {$content='';},
                                        {"m:Locator" => sub {$hash->{helper}{lastchunk} = $_->text_only();},}
                                    ],
                                        
        "GetChannelList"        =>  [sub {$content="<ltv:ChannelListView>".$actPar1."</ltv:ChannelListView>
                                        <ltv:QueryParameters>
                                        <ltv:Range startIndex='".(defined($actPar2)?$actPar2:0)."' maxItems='100'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="m:GetChannelListResponse"},
                                        {"m:ChannelListView" => sub { LoeweTV_ChannelList_View( $hash, $_->text_only('m:AccessStatus') );},
                                          "m:ResultItemFragment" => sub { LoeweTV_ChannelList_Fragment( $hash, $_->att("sequenceNumber"), $_->att("totalResults"), $_->att("returnedResults"), $_->att("startIndex") );},
                                        "m:ResultItemReference" => sub { LoeweTV_ChannelList_Reference( $hash, $_->att("mediaItemUuid") );}}
                                    ],
                                        
        "GetListOfChannelLists" =>  [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$actPar1."' maxItems='".($actPar1+100)."'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="m:ResultItemChannelLists"}
                                    ],
                                        
        "GetMediaItem"          =>  [sub {$content='<MediaItemReference mediaItemUuid="'.$actPar1.'"/>';$result="m:ShortInfo"}],
            
########## untested            
        "GetMediaEvent"         =>  [sub {$content='<MediaEventReference mediaEventUuid="'.$actPar1.'"/>';$result="m:ShortInfo"}],
            
        "GetChannelInfo"        =>  [sub {$content=""}],
            
        "GetCurrentEvent"       =>  [sub {$content="<ltv:Player>0</ltv:Player>";},
                                        {"m:Name" => sub {$hash->{curevent}[0] = $_->text("m:Name");},
                                        "m:ExtendedInfo" => sub {$hash->{curevent}[1] = $_->text("m:ExtendenInfo");},
                                        "m:Locator" => sub {$hash->{curlocator} = $_->text_only("m:Locator");}},
                                    ],
                                        
        "GetNextEvent"          => [sub {$content="<ltv:Player>0</ltv:Player>";$result="m:GetNextEventResponse"}],
            
        "SetActionField"        => [sub {$content="<ltv:InputText>".$actPar1."</ltv:InputText>";$result="m:Result"}],
            
        "GetDRPlusArchive"      => [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$actPar1."' maxItems='1000'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="ltv:ResultItemDRPlusFragment"}
                                    ],
    );

   Log3 $name, 2, "STARTING SENDREQUEST: $action";
   
   
   # ??? hash for params need to be moved to initialize
   
    my %hu_sr_params = (
                    url        => "http://".$hash->{HOST}.":905/loewe_tablet_0001",
                    timeout    => 30,
                    method     => "POST",
                    header     => "",
                    callback   => \&LoeweTV_HU_Callback
    );

    $hash->{HU_SR_PARAMS} = \%hu_sr_params;
    
    # create hash for storing readings for update
    my %hu_sr_readings = ();
    $hash->{HU_SR_PARAMS}->{SR_READINGS} = \%hu_sr_readings;
    
    #$action = "GetDeviceData" if( ! defined($action));
    
    my $xmlheader = "<?xml version='1.0' encoding='UTF-8'?>\n<env:Envelope
        xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\"
        xmlns:ltv=\"urn:loewe.de:RemoteTV:Tablet\">\n<env:Body>\n";
    
    my $action_xml1 = "<ltv:$action>\n";
    
    my $xmlheader2 = "<ltv:fcid>".$hash->{FCID}."</ltv:fcid>
            <ltv:ClientId>".$hash->{CLIENTID}."</ltv:ClientId>\n";

    my $action_xml2 = "\n</ltv:$action>";
    
    my $footer = "\n</env:Body></env:Envelope>\n";
    

    if ($actions{$action}[0]) {
        $actions{$action}[0]->();
        $handlers=$actions{$action}[1];
    
    } else {
        print "Unknown action: $action\n";
    };

    # Aufbau der Messages
    $message = $xmlheader.$action_xml1.$xmlheader2.$content.$action_xml2.$footer;
  

    # construct the HTTP header
    
    # ??? move to global
    my $LoeweTV_header = "User-Agent: Assist Media/23 CFNetwork/808 Darwin/16.0.0\r\n".
      "Accept: */*\r\n".
      "Accept-Encoding: gzip, deflate\r\n".
      "Accept-Language: de-de\r\n".
      "Content-Type: application/soap+xml; charset=utf-8\r\n".
      "Connection: keep-alive";

    $hash->{HU_SR_PARAMS}->{header} = $LoeweTV_header.
      "\r\n"."SOAPAction: ".$action;

    $hash->{HU_SR_PARAMS}->{data} = $message;

    $hash->{HU_SR_PARAMS}->{action} = $action;

    $hash->{HU_SR_PARAMS}->{handlers} = $handlers;
  
    $hash->{HU_SR_PARAMS}->{hash} = $hash;

    Log3 $name, 2, "Sub LoeweTV_SendRequest ($name) - Request: ".Dumper($message);
    
    # send the request non blocking
    if ( defined( $ret ) ) {
      Log3 $name, 1, "LoeweTV_SendRequest $name: Failed with :$ret:";
      LoeweTV_HU_Callback( $hash->{HU_SR_PARAMS}, $ret, "");

    } else {
      $hash->{HU_DO_PARAMS}->{args} = \@args;
      
      Log3 $name, 4, "LoeweTV_SendRequest $name: call url :".$hash->{HU_SR_PARAMS}->{url}.": ";
      HttpUtils_NonblockingGet( $hash->{HU_SR_PARAMS} );

    }
}


#####################################
#  INTERNAL: Callback is the callback for any nonblocking call to the TV
#   3 params are defined for callbacks
#     param-hash
#     err
#     data (returned from url call)
# empty string used instead of undef for no return/err value
sub LoeweTV_HU_Callback($$$)
{
  my ( $param, $err, $data ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};

  my $ret;
  my $action = $param->{action};

  Log3 $name, 2, "LoeweTV_HU_Callback $name: ".
    (defined( $err )?"status err :".$err.":":"no error").
    "     data :".(( defined( $data ) )?$data:"<undefined>");

  if ( $err ne "" ) {
    $ret = "Error returned: $err";
    $hash->{lastresponse} = $ret;
  } elsif ( $param->{code} != 200 ) {
    $ret = "HTTP-Error returned: ".$param->{code};
    $hash->{lastresponse} = $ret;
  } else {
  
    my $handlers = $param->{handlers};
    my $twig2;
  
    Log3 $name, 2, "LoeweTV_HU_Callback $name: action: ".$action."   code : ".$param->{code};

    if ( ( defined($data) ) && ( $data ne "" ) ) {
      Log3 $name, 2, "LoeweTV_HU_Callback $name: handle XML values";
      $twig2 = XML::Twig->new(twig_handlers => $handlers,keep_encoding => 1)->parse($data);
    }
    
    $hash->{lastresponse} = $data;
    $ret = "SUCCESS";
  }

  # handle readings
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "requestAction", $action );   
  readingsBulkUpdate($hash, "requestResult", $ret );   
  
  if ( $ret eq  "SUCCESS" ) {
    Log3 $name, 2, "LoeweTV_HU_Callback $name: update readings";
    my $refreadings = $param->{SR_READINGS};
    foreach my $readName ( keys %$refreadings ) {
      Log3 $name, 2, "LoeweTV_HU_Callback $name: reading: ".$readName."   value :".$refreadings->{$readName}.":";
      if ( defined( $refreadings->{$readName} ) ) {
        readingsBulkUpdate($hash, $readName, $refreadings->{$readName} );        
      } else {
        delete($hash->{READINGS}{$readName}); 
      }
    }
  }
  readingsEndUpdate($hash, 1);   
  
  # clean param hash
  delete( $param->{data} );
  delete( $param->{code} );
  
  $hash->{doStatus} = "";

  #########################
  # start next command in queue if available
  if ( ( defined( $hash->{actionQueue} ) ) && ( scalar( @{ $hash->{actionQueue} } ) ) ) {
    my $ref = shift @{ $hash->{actionQueue} };
    Log3 $name, 4, "LoeweTV_HU_Callback $name: handle queued cmd with :@$ref[0]: ";
    LoeweTV_SendRequest( $hash, @$ref[0], @$ref[1], @$ref[2] );
  }
  

}

    


############ Presence Erkennung Begin #################
sub LoeweTV_Presence($) {

    my $hash    = shift;    
    my $name    = $hash->{NAME};
    
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("LoeweTV_PresenceRun", $name.'|'.$hash->{HOST}, "LoeweTV_PresenceDone", 5, "LoeweTV_PresenceAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}) );
}

sub LoeweTV_PresenceRun($) {

    my $string          = shift;
    my ($name, $host)   = split("\\|", $string);
    
    my $tmp;
    my $response;

    
    $tmp = qx(ping -c 3 -w 2 $host 2>&1);

    if(defined($tmp) and $tmp ne "") {
    
        chomp $tmp;
        Log3 $name, 5, "LoeweTV ($name) - ping command returned with output:\n$tmp";
        $response = "$name|".(($tmp =~ /\d+ [Bb]ytes (from|von)/ and not $tmp =~ /[Uu]nreachable/) ? "present" : "absent");
    
    } else {
    
        $response = "$name|Could not execute ping command";
    }
    
    Log3 $name, 4, "Sub LoeweTV_PresenceRun ($name) - Sub finish, Call LoeweTV_PresenceDone";
    return $response;
}

sub LoeweTV_PresenceDone($) {

    my ($string)            = @_;
    
    my ($name,$response)    = split("\\|",$string);
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 4, "Sub LoeweTV_PresenceDone ($name) - Der Helper ist disabled. Daher wird hier abgebrochen" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    readingsSingleUpdate($hash,'presence',$response,1);
    
    Log3 $name, 4, "Sub LoeweTV_PresenceDone ($name) - Abschluss!";
}

sub LoeweTV_PresenceAborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    
    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,'presence','timedout', 1);
    
    Log3 $name, 4, "Sub LoeweTV_PresenceAborted ($name) - The BlockingCall Process terminated unexpectedly. Timedout!";
}

####### Presence Erkennung Ende ############


############ Helper #################
sub LoeweTV_IsPresent($) {
    my $hash = shift;
    return (ReadingsVal($hash->{NAME},'presence','absent') eq 'present');
}

sub LoeweTV_HasAccess($) {
    my $hash = shift;
    return (ReadingsVal($hash->{NAME},'access','undef') eq 'accepted');
}


1;


=pod
=item device
=item summary control for Loewe TV devices via network connection
=item summary_DE Steuerung von Loewe TV Ger&auml;ten &uuml;ber das Netzwerk
=begin html

<a name="LoeweTV"></a>
<h3>LoeweTV</h3>

=end html

=begin html_DE

<a name="LoeweTV"></a>
<h3>LoeweTV</h3>

=end html_DE

=cut
