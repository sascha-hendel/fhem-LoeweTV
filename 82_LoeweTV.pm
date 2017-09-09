###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - der.einstein      Thanks for Commit
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
##




package main;

use strict;
use warnings;


my $missingModul = "";
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use HTTP::Request::Common;1" or $missingModul .= "HTTP::Request::Common ";
eval "use XML::Twig;1" or $missingModul .= "XML::Twig ";

use Blocking;


my $version = "0.0.23";


# Declare functions
sub LoeweTV_Define($$);
sub LoeweTV_Undef($$);
sub LoeweTV_Initialize($);
sub LoeweTV_Get($@);
sub LoeweTV_Set($@);
sub LoeweTV_WakeUp_Udp($@);
sub LoeweTV_CheckAccess($);
sub LoeweTV_SendRequest($$$);
sub LoeweTV_ResponseProcessing($$);
sub LoeweTV_WriteReadings($$);
sub LoeweTV_Presence($);
sub LoeweTV_PresenceRun($);
sub LoeweTV_PresenceDone($);
sub LoeweTV_PresenceAborted($);




sub LoeweTV_Initialize($) {
    my ($hash) = @_;
    
    #$hash->{GetFn}      = "LoeweTV_Get";
    $hash->{SetFn}      = "LoeweTV_Set";
    $hash->{DefFn}      = "LoeweTV_Define";
    $hash->{UndefFn}    = "LoeweTV_Undef";

    $hash->{AttrList}   =  "fhemMAC " .
                        "interval " .
                        #"ip " .
                        #"tvmac " .
                        #"action " .
                        #"RCkey " .
                        #"clientid " .
                        #"fcid " .
                        #"status:accepted,Pending,Denied,undef " .
                        #"connectsuccess:true,false " .
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
    
    
    Log3 $name, 3, "LoeweTV $name: defined LoeweTV device";
    
    $modules{LoeweTV}{defptr}{HOST} = $hash;
    readingsSingleUpdate($hash,'state','initialized',1);
    
    LoeweTV_Presence($hash);
    
    
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
            LoeweTV_InternalTimerGetDeviceData($hash);
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL}   = 15;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "LoeweTV ($name) - delete User interval and set default: 300";
            LoeweTV_InternalTimerGetDeviceData($hash);
        }
    }

    return undef;
}

sub LoeweTV_FirstRun($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    
    
    if(ReadingsVal($name,'presence','absent') eq 'present') {
    
        LoeweTV_SendRequest($hash,'GetDeviceData',0);
        
    } else {
    
        readingsSingleUpdate($hash,'state','off',1);
    }
    
    InternalTimer( gettimeofday()+10, "LoeweTV_TimerStatusRequest", $hash, 1 );
}

sub LoeweTV_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    my ($action,$RCkey);

    
    if( lc $cmd eq 'setactionfield' ) {

    } elsif( lc $cmd eq 'setvolume' ) {
    
    } elsif( lc $cmd eq 'setmute' ) {
    
    } elsif( lc $cmd eq 'connect' ) {
    
    } elsif( lc $cmd eq 'wakeup' ) {
    
        LoeweTV_WakeUp_Udp($hash,$hash->{HOST},$hash->{TVMAC});
        return;
    
    } elsif( lc $cmd eq '' ) {
    
    
    } elsif( lc $cmd eq '' ) {
    
    
    } else {
    
        my $list    = 'SetActionField SetVolume:slider,0,1,100 SetMute:on,off connect:noArg WakeUp:noArg';
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    
#     $hash->{helper}{RCkey} = "" if( not defined $hash->{helper}{RCkey} );
#     
#     $hash->{helper}{fcid} = "1234" if( not defined $hash->{helper}{fcid} );
#     
#     LoeweTV_hostUp($hash);
# 
#     
#     if (! defined $hash->{CLIENTID}){$hash->{CLIENTID} = "?"};
#     
#     LoeweTV_CheckAccess($hash,$hash->{CLIENTID},$hash->{FCID});
#     
#     if ($hash->{status} eq "accepted") 	{LoeweTV_SendRequest($hash,$action,$RCkey);}
    
    
    
    LoeweTV_SendRequest($hash,$action,$RCkey) if(ReadingsVal($name,'presence','absent') eq 'present');
    
    
    Log3 $name, 5, "LoeweTV $name: called function LoeweTV_Set()";
    return undef;
}

sub LoeweTV_TimerStatusRequest($) {

### Hier kommen dann die Sachen rein welche alle x Sekunden ausfegührt werden um Infos zu erhalten
### presence zum Beispiel





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

sub LoeweTV_CheckAccess($) {

    my ($hash)      = shift;
    my $name        = $hash->{NAME};
    my $n           = 1;
    
    
    while ((ReadingsVal($name,'state','denied') ne "accepted") and ($n<=3)) {
    
        $n=$n+1;
        LoeweTV_SendRequest($hash,"RequestAccess",0)
    };
    
    
    
    print "run CHECKACCESS: ReadingsVal($name,'state','denied')   \n";
    
    
    return(ReadingsVal($name,'state','denied'));
    
    
    }

sub LoeweTV_SendRequest($$$) {

    my($hash, $action, $RCkey)  = @_;
    
    my $name                    = $hash->{NAME};

    my ($message, $response, $request, $userAgent, $noob, $twig2, $content, $handlers);
    our $result ="";
    my %actions = (
        "RequestAccess"         =>  [sub {$content='<ltv:DeviceType>Apple iPad</ltv:DeviceType>
                                        <ltv:DeviceName>FHEM</ltv:DeviceName>
                                        <ltv:DeviceUUID>'.$hash->{mac}.'</ltv:DeviceUUID>
                                        <ltv:RequesterName>Assist Media App</ltv:RequesterName>'},
                                        {'m:ClientId' => sub {$hash->{CLIENTID} = $_->text_only('m:ClientId');},
                                        'm:AccessStatus' => sub {readingsSingleUpdate($name,'state',"$_->text_only('m:AccessStatus'",1);},}
                                    ],
                                    
        "InjectRCKey"           =>  [sub {$content='<InputEventSequence>
                                        <RCKeyEvent alphabet="l2700" value="'.$RCkey.'" mode="press"/>
                                        <RCKeyEvent alphabet="l2700" value="'.$RCkey.'" mode="release"/>
                                        </InputEventSequence>'}],
                                        
        "GetDeviceData"         =>  [sub {$content='';$result="m:MAC-Address"}],
            
        "GetChannelList"        =>  [sub {$content="<ltv:ChannelListView>".$RCkey."</ltv:ChannelListView>
                                        <ltv:QueryParameters>
                                        <ltv:Range startIndex='".$ARGV[4]."' maxItems='9999'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="m:GetChannelListResponse"}
                                    ],
                                        
        "GetListOfChannelLists" =>  [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$RCkey."' maxItems='9999'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="m:ResultItemChannelLists"}
                                    ],
                                        
        "GetMediaItem"          =>  [sub {$content='<MediaItemReference mediaItemUuid="'.$RCkey.'"/>';$result="m:ShortInfo"}],
            
        "GetMediaEvent"         =>  [sub {$content='<MediaEventReference mediaEventUuid="'.$RCkey.'"/>';$result="m:ShortInfo"}],
            
        "GetChannelInfo"        =>  [sub {$content=""}],
            
        "GetCurrentPlayback"    =>  [sub {$content='';},
                                        {"m:Locator" => sub {$hash->{lastchunk} = $_->text_only();},}
                                    ],
                                        
        "GetCurrentEvent"       =>  [sub {$content="<ltv:Player>0</ltv:Player>";},
                                        {"m:Name" => sub {$hash->{curevent}[0] = $_->text("m:Name");},
                                        "m:ExtendedInfo" => sub {$hash->{curevent}[1] = $_->text("m:ExtendenInfo");},
                                        "m:Locator" => sub {$hash->{curlocator} = $_->text_only("m:Locator");}},
                                    ],
                                        
        "GetNextEvent"          => [sub {$content="<ltv:Player>0</ltv:Player>";$result="m:GetNextEventResponse"}],
            
        "SetActionField"        => [sub {$content="<ltv:InputText>".$RCkey."</ltv:InputText>";$result="m:Result"}],
            
        "SetVolume"             => [sub {$content="<Value>".$RCkey."</Value>";$result="m:Value"}],
            
        "GetVolume"             => [sub {$content="";$result="m:Value"}],
            
        "SetMute"               => [sub {$content="<Value>".$RCkey."</Value>";$result="m:Value"}],
            
        "GetMute"               => [sub {$content="";$result="m:Value"}],
            
        "GetDRPlusArchive"      => [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$RCkey."' maxItems='1000'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="ltv:ResultItemDRPlusFragment"}
                                    ],
    );

    
    print "STARTING SENDREQUEST: $action   \n";
    
    #$action = "GetDeviceData" if( ! defined($action));
    
    my $header = "<env:Envelope
        xmlns:env='http://schemas.xmlsoap.org/soap/envelope/'
        xmlns:ltv='urn:loewe.de:RemoteTV:Tablet'><env:Body>\n";
    
    my $action_xml1 = "<ltv:$action>\n";
    
    my $header2 = "<ltv:fcid>".$hash->{FCID}."</ltv:fcid>
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
    $message = $header.$action_xml1.$header2.$content.$action_xml2.$footer;
    
    
    # Aufbau der HTTP Verbindung
    $request = HTTP::Request->new(POST => 'http://'.$hash->{ip}.':905/loewe_tablet_0001');
    
    # Aufbau des Agents
    $userAgent = LWP::UserAgent->new(agent => 'Assist Media/23 CFNetwork/808 Darwin/16.0.0');
    
    Aufbau des Headers
    $request->header('Accept' => '*/*');
    $request->header('Accept-Encoding' => 'gzip, deflate');
    $request->header('Accept-Language' => 'de-de');
    $request->header('Connection' => 'keep-alive');
    
    $request->header('SOAPAction' => $action);
    
    # !!!
    $request->content_type("application/soap+xml; charset=utf-8");
    
    # ???
    $request->content($message);
    $response = $userAgent->request($request);
    
    
    $noob = $response->content;
    
    $twig2 = XML::Twig->new(twig_handlers => $handlers,keep_encoding => 1)->parse($noob);
    
    
    LoeweTV_ResponseProcessing($hash,$response);
}
    
    
sub LoeweTV_ResponseProcessing($$) {
    
    my ($hash,$response)        = @_;
    
    my $name                    = $hash->{NAME};
    
    Log3 $name, 2, "Sub LoeweTV_PresenceRun ($name) - Response: $response->error_as_HTML";
    Log3 $name, 2, "Sub LoeweTV_PresenceRun ($name) - Response: $response->content";
    
    if($response->code == 200) {
        $hash->{connectsuccess} = "true";	
        $hash->{lastresponse} = $response->content;
    
    } else {
        $hash->{connectsuccess} = "false";
        $hash->{lastresponse} = $response->error_as_HTML;
    }
    
    if($hash->{action} eq "RequestAccess"){
        return($hash->{status})
    }else{
        return($hash->{status})
    };
}

sub LoeweTV_WriteReadings($$) {




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
