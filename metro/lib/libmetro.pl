# $Id: libmetro.pl,v 1.2 2008/06/26 07:13:14 boggia Exp $
###########################################################
#   Creation : 26/03/08 : boggia
# 
#Fichier contenant les fonctions g�n�riques des programmes
# de m�trologie
###########################################################

###########################################################
# fonction de lecture de fichier de conf
# prend un fichier de conf et une variable recherchee en param
# renvoie la valeur de la variable
# appelee par :
# read_conf_file("nom_fichier_conf","variable_recherchee"); 
#
sub read_conf_file
{
    my ($file,$var) = @_;

    my $line;

    open(CONFFILE, $file);
    while($line=<CONFFILE>)
    {
        if( $line!~ /^#/ && $line!~ /^\s+/)
        {
            chomp $line;
            my ($variable,$value) = (split(/\s+/,$line))[0,1];
            if($variable eq $var)
            {
                close(CONFFILE);
                return $value;
            }
        }
    }
    close(CONFFILE);

    return "UNDEF";
}

###########################################################
# fonction de lecture de la globalite du fichier de conf
# prend un fichier de conf et stocke la totalit� des
# variables du un tableau associatif
sub read_global_conf_file
{
    my ($file) = @_;
    
    my $line;

    open(CONFFILE, $file);
    while($line=<CONFFILE>)
    {
	if( $line!~ /^#/ && $line!~ /^\s+/)
	{   
	    chomp $line;
	    my ($variable,$value) = (split(/\s+/,$line))[0,1];

	    $var{$variable} = $value;
	}
    }
    close(CONFFILE);

    return %var;
}

###########################################################
# fonction de nettoyage de chaines de caract�res
# enl�ve les espaces � la fin d'une chaine de char
sub clean_var
{
    my ($string) = @_;

    my $s = $string;
    my $test = chop $s;
    
    if($test eq " ")
    {
	$string = $s;	
    }

    return $string;
}


###########################################################
# resolution de nom inverse.
sub gethostnamebyaddr
{
    my ($ip) = @_;

    my $iaddr = inet_aton($ip);    
#my $hostname  = gethost($ip)->name;
    my $hostname  = gethostbyaddr($iaddr, AF_INET);
    ($hostname)=(split(/\./,$hostname))[0];

    return $hostname;
}


###########################################################
# resolution de nom.
sub getaddrbyhostname
{
    my ($hostname) = @_;

    my $packed_ip = gethostbyname($hostname);
    if (defined $packed_ip) 
    {
 	return inet_ntoa($packed_ip); 
    }
    else
    {
	return -1;
    }
}


#########################################################
# Convertit une chaine de date de la base SQL
# au format time_t en heure locale
#
sub dateSQL2time 
{
    my ($date) = @_ ;

    my $gmt = 0;
    my @ltime ;
    my $t = 0;
    my ($a, $m, $j, $h, $mi, $s) ;

    # Format :
    # 2005-05-18 10:02:53.980149
    # 2007-04-27 12:03:17.980149
    if($date=~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) 
    {
        $a = $1 - 1900;
        $m = $2 - 1 ;
        $j = $3 ;
        $h = $4 ; $mi= $5 ; $s = $6 ;

        if($a < 70 || !$a)
        {
            $a = 70;
            $m = 0;
        }

        $t=mktime($s,$mi,$h,$j,$m,$a,0,0,0);
    }
    return $t ;
}


###########################################################
# conversion des d�bits max en bits/s en X*10eY
# 100000000 -> 1.0000000000+e08
sub convert_nb_to_exp
{
    my ($speed) = @_;

    if($speed=~/[0-9]+/)
    {
        my @chiffres = split(//,$speed);
        my $nb_exp = "$chiffres[0].";
        my $t_chiffres = @chiffres;
        my $i;
        for($i=1;$i<11;$i++)
        {
            if($chiffres[$i])
            {
                $nb_exp = "$nb_exp" . "$chiffres[$i]";
            }
            else
            {
                $nb_exp = "$nb_exp" . "0";
            }
        }
        $t_chiffres --;
        if($t_chiffres < 10)
        {
            $nb_exp = "$nb_exp" . "e+0$t_chiffres";
        }
        else
        {
            $nb_exp = "$nb_exp" . "e+$t_chiffres";
        }
        return $nb_exp;
    }
    else
    {
        return -1;
    }
}


###########################################################
#
# Renvoie la date decomposee par champs dans un tableau nominatif.
# Prend en parametre l'heure en time_t
# Sinon utilise l'heure d'execution de la fonction
#
sub get_time
{
        my ($time) = @_;

        my %t;

        if($time !~/[0-9]+/)
        {
                $time = time;
        }

        ($t{SEC},$t{MIN},$t{HOUR},$t{MDAY},$t{MON},$t{YEAR},$t{WDAY},$t{YDAY},$t{isDST}) = localtime($time);

        $t{YEAR} += 1900;
        $t{MON} += 1;

        return %t;
}

###########################################################
# donne une limite de d�bit maximum aux mesures inscrites 
# dans une base
sub setBaseMaxSpeed
{
    my ($base,$speed) = @_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    my $maxspeed = convert_nb_to_exp($speed);
    system("$rrdtool tune $base --maximum input:$maxspeed");
    system("$rrdtool tune $base --maximum output:$maxspeed");
}

###########################################################
# retourne la vitesse d'une interface
sub get_snmp_ifspeed
{
    my ($param,$index,$interf) = @_;

    my $speed;

    # recherche de l'interface dans le tableau des interfaces
    foreach my $key (keys %var)
    {
        if($key=~/^IFSPEED_/)
        {
		my $nameif = $key;
		($nameif) = (split(/IFSPEED_/,$key))[1];
		if($interf=~/$nameif/)
		{
                	$speed = $var{$key};
		}
        }
    }

    # si le nom de l'interface ne matche pas les interfaces connues
    if($speed eq "")
    {
        if($index eq "")
        {
                # recuperation de l'oid de l'interface
                $index = get_snmp_ifindex($param,$interf);
        }
        #&snmpmapOID("speed","1.3.6.1.2.1.2.2.1.5.$index");
        &snmpmapOID("speed","1.3.6.1.2.1.31.1.1.1.15.$index");
        my @speed = &snmpget($param, "speed");
        $speed = $speed[0];
	print "$param,$interf => $speed\n";
    }

    if($speed ne "")
    {
        $speed = $speed*1000000;

        return $speed;
    }
    else
    {
        writelog("cree-base-metro","","info",
            "\t ERREUR : Vitesse de ($param,$interf,index : $index) non definie, force � 100 Mb/s");
        return 100000000;
    }
}

###########################################################
# retourne l'index de l'interface par rapport a un nom
sub get_snmp_ifindex
{
    my ($param,$if) = @_;

    # recuperation de l'oid de l'interface
    &snmpmapOID("desc","1.3.6.1.2.1.2.2.1.2");
    my @desc_inter = &snmpwalk($param, "desc");
    my $nb_desc = @desc_inter;
    my $index_interface;
    my $i;
    for($i=0;$i<$nb_desc;$i++)
    {
        if($desc_inter[$i]=~m/$if/)
        {
            $index_interface = (split(/:/,$desc_inter[$i]))[0];
            $index_interface = (split(/\s/,$index_interface))[0];

            return $index_interface;
        }
    }
    return -1;
}


###########################################################
# creation de la Base RRD pour le trafic sur un port ainsi 
# que la disponibilite reseau
sub creeBaseTrafic
{
    my ($fichier,$speed)=@_;
 
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U DS:erreur:GAUGE:600:U:U DS:ticket:GAUGE:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    setBaseMaxSpeed($fichier,$speed);
}

###########################################################
# creation de la Base RRD pour le trafic de broadcast sur 
# un port ainsi que la disponibilite reseau
sub creeBaseBroadcast
{
    my ($fichier,$speed)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:8760 RRA:MAX:0.5:24:8760");
    setBaseMaxSpeed($fichier,$speed);
}

###########################################################
# creation d'une base rrd pour un compteur generique
sub creeBaseCounter
{
    my ($fichier,$speed) = @_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:value:COUNTER:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    my $maxspeed = convert_nb_to_exp($speed);
    system("$rrdtool tune $fichier --maximum value:$maxspeed");
}

###########################################################
# creation d'une base RRD de trafic sp�cifique aux points
# d'acces
sub creeBaseOsirisAP
{
    my ($fichier,$speed)=@_;
    
    my $rrdtool = read_conf_file($conf_file "RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    setBaseMaxSpeed($fichier,$speed);
}

###########################################################
# creation d'une base d'associations aux AP
sub creeBaseApAssoc
{
    my ($fichier)=@_;
    
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:wpa:GAUGE:600:U:U DS:clair:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# METROi : creation d'une base d'associes ou d'authentifies 
# pour un AP WiFi
sub creeBaseAuthassocwifi
{
    my ($fichier,$ssid)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("/usr/bin/rrdtool create $fichier DS:$ssid:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour une collecte des 
# donnees en % de la CPU
sub creeBaseCPU
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");	
    system("$rrdtool create $fichier DS:cpu_system:GAUGE:600:U:U DS:cpu_user:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte du 
# nombre d'interruptions systeme d'une machine
sub creeBaseInterupt
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:interruptions:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte du
# load average d'une machine
sub creeBaseLoad
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");	
    system("$rrdtool create $fichier DS:load_5m:GAUGE:600:U:U DS:load_15m:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# l'utilisation de la memoire et du swap
sub creeBaseMemory
{
    my ($fichier)=@_;
	
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:memoire:GAUGE:600:U:U DS:swap:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# l'utilisation de la CPU d'un �quipement Cisco
sub creeBaseCPUCisco
{
    my ($fichier)=@_;
 
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:cpu_1min:GAUGE:600:U:U DS:cpu_5min:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}


###########################################################
# fonction de creation d'une base RRD pour la collecte de
# l'utilisation de la CPU de la routing Engine d'un Juniper M20
sub creeBaseCPUJuniper
{
    my ($fichier)=@_;
 
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:cpu0:GAUGE:600:U:U DS:cpu1:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction  qui cr�e une base qui stocke les stats du d�mon
# bind
sub creeBaseBind_stat
{
     my ($fichier)=@_;
    
     my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");

     system("$rrdtool create $fichier DS:success:COUNTER:600:U:U DS:failure:COUNTER:600:U:U DS:nxdomain:COUNTER:600:U:U DS:recursion:COUNTER:600:U:U DS:referral:COUNTER:600:U:U DS:nxrrset:COUNTER:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
     system("/usr/bin/rrdtool tune $fichier --maximum success:3.0000000000e+04");
     system("/usr/bin/rrdtool tune $fichier --maximum failure:3.0000000000e+04");
     system("/usr/bin/rrdtool tune $fichier --maximum nxdomain:3.0000000000e+04");
     system("/usr/bin/rrdtool tune $fichier --maximum recursion:3.0000000000e+04");
     system("/usr/bin/rrdtool tune $fichier --maximum referral:3.0000000000e+04");
     system("/usr/bin/rrdtool tune $fichier --maximum nxrrset:3.0000000000e+04");
}

sub creeBaseTPSDisk
{
     my ($fichier)=@_;
 
     my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
 
     system("$rrdtool create $fichier DS:ioreads:COUNTER:600:U:U DS:iowrites:COUNTER:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
    system("$rrdtool tune $fichier --maximum ioreads:1.0000000000e+06 iowrites:1.0000000000e+06");
}


sub creeBaseMailq
{
     my ($fichier)=@_;
     
     my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
     system("$rrdtool create $fichier DS:mailq:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

sub creeBaseOsirisCE
{
     my ($fichier)=@_;

     my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
     system("$rrdtool create $fichier  DS:input:COUNTER:600:U:U DS:output:COUNTER:600:U:U DS:erreur:GAUGE:600:U:U DS:ticket:GAUGE:600:U:U RRA:AVERAGE:0.5:1:525600 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
     system("$rrdtool tune $fichier --maximum input:2.0000000000e+09 output:2.0000000000e+09");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en secondes sous forme de jauge
sub creeBaseTpsRepWWW
{
     my ($fichier)=@_;

     my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
     system("$rrdtool create $fichier DS:time:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en secondes sous forme de jauge pour une
# interrogation toutes les minutes
sub creeBaseTpsRepWWWFast
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier -s 60 DS:time:GAUGE:120:U:U RRA:AVERAGE:0.5:1:1051200 RRA:AVERAGE:0.5:60:43800 RRA:MAX:0.5:60:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseVolumeOctets
{
    my ($fichier)=@_;
 
    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:octets:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseNbMbuf
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:mbuf:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge
sub creeBaseNbGeneric
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:value:GAUGE:600:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction de creation d'une base RRD pour la collecte de
# de valeurs en octets sous forme de jauge pour une
# interrogation toutes les minutes
sub creeBaseVolumeOctetsFast
{
    my ($fichier)=@_;

    my $rrdtool = read_conf_file($conf_file,"RRDTOOL_EXEC");
    system("$rrdtool create $fichier DS:octets:GAUGE:120:U:U RRA:AVERAGE:0.5:1:210240 RRA:AVERAGE:0.5:24:43800 RRA:MAX:0.5:24:43800");
}

###########################################################
# fonction qui controle la validit�'une adresse IP
# et son appartenance au reseau d'access
sub ctrl_ip
{
        my ($ip)=@_;
        my $ip_val = 0;

        if($ip =~/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
        {
		if($1<=255 && $2<=255 && $3<=255 && $4<=255)
                {
                        $ip_val = 1;
                }
        }
        else
        {
                # writelog("ctrl_ip","","info",
                #        "\t -> ERROR : READ SUP : mauvais format d'adresse IP: '$ip'");
                $return -1;
        }
        return($ip_val);
}

###########################################################
# controle snmp d'un host dans le but de recuperer le 
# sysoid
# si ok, renvoie l'oid de l'equipement
# sinon renvoie -1
sub check_host
{
	my ($ip,$snmp_com) = @_;
	
	my $param = $snmp_com."@".$ip;
        &snmpmapOID("oid","1.3.6.1.2.1.1.2.0");
        my @sys_oid = &snmpget($param,"oid");
	
	if($sys_oid[0] ne "")
    	{
        	return $sys_oid[0];
    	}
    	else
    	{
        	writelog("check_host","","info",
            	"\t ERREUR : Echec interrogation SNMP pour sysoid ($param)");
        	
		return -1;
    	}
}


#############################################################
# lecture d'un tableau associatif a 2 dimensions
#
sub read_tab_asso
{
        my (%t) = @_;

        foreach my $key (sort keys %t)
        {
                print "$key {\n";
                foreach my $kkey (keys %{$t{$key}})
                {
                        print "\t$kkey -> $t{$key}{$kkey}\n";
                }
                print "}\n";
        }
}




return 1;