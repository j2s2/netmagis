#
# $Id: parse-hp.tcl,v 1.3 2008-09-29 16:45:56 pda Exp $
#
# Package d'analyse de fichiers de configuration IOS HP
#
# Historique
#   2008/07/07 : pda/jean : d�but de la conception
#

###############################################################################
# Fonctions utilitaires
###############################################################################

#
# Entr�e :
#   - idx = eq!<eqname>
#   - iface = <iface>
# Remplit
#   - tab(eq!<nom eq>!if) {<ifname> ... <ifname>}
#
# Historique
#   2008/07/21 : pda/jean : conception
#

proc hp-ajouter-iface {tab idx iface} {
    upvar $tab t

    if {[lsearch -exact $t($idx!if) $iface] == -1} then {
	lappend t($idx!if) $iface
	if {! [info exists t($idx!if!$iface!link!name)]} then {
	    hp-set-ifattr t $idx!if!$iface "name" "X"
	    hp-set-ifattr t $idx!if!$iface "stat" "-"
	    hp-set-ifattr t $idx!if!$iface "desc" ""
	}
    }
}

###############################################################################
# Analyse du fichier de configuration
###############################################################################

#
# Entr�e :
#   - libdir : r�pertoire contenant les greffons d'analyse
#   - model : mod�le de l'�quipement (ex: M20)
#   - fdin : descripteur de fichier en entr�e
#   - fdout : fichier de sortie pour la g�n�ration
#   - eq = <eqname>
# Remplit :
#   - tab(eq)	{<eqname> ... <eqname>}
#   - tab(eq!ios) "unsure|router|switch"
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse {libdir model fdin fdout tab eq} {
    upvar $tab t
    array set kwtab {
	-COMMENT			^;
	interface			{CALL hp-parse-interface}
	vlan				{CALL hp-parse-vlan}
	exit				{CALL hp-parse-exit}
	disable				{CALL hp-parse-disable}
	name				{CALL hp-parse-name}
	trunk				{CALL hp-parse-trunk}
	snmp-server			NEXT
	snmp-server-community		{CALL hp-parse-snmp-community}
	untagged			{CALL hp-parse-untagged}
	tagged				{CALL hp-parse-tagged}
    }

    #
    # On charge la biblioth�que de fonctions "cisco" pour b�n�ficier
    # de la meeeeeerveilleuse fonction "post-process"
    #

    set error [charger $libdir "parse-cisco.tcl"]
    if {$error} then {
	return $error
    }

    #
    # Analyse du fichier
    #

    set t(eq!$eq!context) ""
    set t(eq!$eq!if) {}
    set t(eq!$eq!if!disabled) {}

    set error [ios-parse $libdir $model $fdin $fdout t $eq kwtab]

    if {! $error} then {
	set error [hp-prepost-process $eq t]
    }

    if {! $error} then {
	set error [cisco-post-process "hp" $model $fdout $eq t]
    }
    return $error
}

#
# Entr�e :
#   - line = "<id>"
#   - idx = eq!<eqname>
# Remplit
#   - tab(eq!<nom eq>!if) {<ifname> ... <ifname>}
#   - tab(eq!<nom eq>!current!if) <ifname>
#   - tab(eq!<nom eq>!if!<ifname>!link!name) ""
#   - tab(eq!<nom eq>!if!<ifname>!link!desc) ""
#   - tab(eq!<nom eq>!if!<ifname>!link!stat) ""
#   - tab(eq!<nom eq>!context) iface
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse-interface {active line tab idx} {
    upvar $tab t

    set line [string trim $line]
    if {[regexp {^[-A-Za-z0-9]+$} $line]} then {
	set t($idx!context) "iface"
	lappend t($idx!if) $line
	set t($idx!current!if) $line
	set t($idx!if!$line!link!name) ""
	set t($idx!if!$line!link!desc) ""
	set t($idx!if!$line!link!stat) ""

	hp-ajouter-iface t $idx $line
    }

    return 0
}

#
# Entr�e :
#   - line = <vlanid>
#   - idx = eq!<eqname>
# Remplit
#   - tab(eq!<nom eq>!lvlan) {<id> ... <id>}
#   - tab(eq!<nom eq>!lvlan!lastid) <id>
#   - tab(eq!<nom eq>!lvlan!<id>!desc) ""  (sera remplac� par parse-vlan-name)
#   - tab(eq!<nom eq>!context) vlan
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse-vlan {active line tab idx} {
    upvar $tab t

    set line [string trim $line]
    if {[regexp {^[0-9]+$} $line]} then {
	set t($idx!context) "vlan"
	set idx "$idx!lvlan"
	lappend t($idx) $line
	set t($idx!lastid) $line
	set t($idx!$line!desc) ""
    }

    return 0
}

#
# Entr�e :
#   - line = <>
#   - idx = eq!<eqname>
#   - tab(eq!<nom eq>!context) iface
# Remplit
#   - tab(eq!<nom eq>!context) ""
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse-exit {active line tab idx} {
    upvar $tab t

    set t($idx!context) ""
    return 0
}

#
# Entr�e :
#   - line = <>
#   - idx = eq!<eqname>
#   - tab(eq!<nom eq>!context) iface
#   - tab(eq!<nom eq>!current!if) <ifname>
# Remplit
#   - tab(eq!<nom eq>!context) ""
#   - tab(eq!<nom eq>!if!disabled) {... <ifname>}
#
# Note : on ne peut pas simplement supprimer l'interface, car elle
#   r�appara�tra plus tard lors de l'analyse des vlans
#
# Historique
#   2008/07/24 : pda      : conception
#

proc hp-parse-disable {active line tab idx} {
    upvar $tab t

    if {[string equal $t($idx!context) "iface"]} then {
	lappend t($idx!if!disabled) $t($idx!current!if)
    }
    return 0
}

#
# Entr�e :
#   - line = <>
#   - idx = eq!<eqname>
#   - tab(eq!<nom eq>!context) "iface" ou "vlan"
#   - tab(eq!<nom eq>!lvlan!lastid) <id>   (si context = "vlan")
#   - tab(eq!<nom eq>!current!if) <ifname> (si context = "iface")
# Remplit
#   - tab(eq!<nom eq>!if!<ifname>!link!desc) <desc>
#   - tab(eq!<nom eq>!if!<ifname>!link!name) <name>
#   - tab(eq!<nom eq>!if!<ifname>!link!stat) <stat>
#	OU
#   - tab(eq!<nom eq>!lvlan!<id>!desc) <desc>
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse-name {active line tab idx} {
    upvar $tab t

    set error 0
    switch $t($idx!context) {
	iface {
	    set ifname $t($idx!current!if)

	    if {[parse-desc $line linkname statname descname msg]} then {
		if {[string equal $linkname ""]} then {
		    warning "$idx: no link name found ($line)"
		    set error 1
		} else {
		    set error [hp-set-ifattr t $idx!if!$ifname name $linkname]
		}
		if {! $error} then {
		    set error [hp-set-ifattr t $idx!if!$ifname stat $statname]
		}
		if {! $error} then {
		    set error [hp-set-ifattr t $idx!if!$ifname desc $descname]
		}
	    } else {
		warning "$idx: $msg ($line)"
		set error 1
	    }
	}
	vlan {
	    set vlanid $t($idx!lvlan!lastid)

	    regsub {^\s*"?(.*)"?\s*$} $line {\1} line

	    # traduction en hexa : cf analyser, fct parse-desc
	    binary scan $line H* line
	    set t($idx!lvlan!$vlanid!desc) $line
	}
	default {
	    warning "Inconsistent context '$t($idx!context)' for name '$line'"
	}
    }

    return $error
}

#
# Entr�e :
#   - line = <iface>-<iface>,... <trunkif> <mode>
#   - idx = eq!<eqname>
# Remplit
#   - tab(eq!<nom eq>!if!<iface>!parentif) <trunkif>	(pour toutes les iface)
#
# Historique
#   2008/07/07 : pda/jean : conception
#

proc hp-parse-trunk {active line tab idx} {
    upvar $tab t

    if {[regexp {^\s*([-A-Za-z0-9,]+)\s+(\S+)} $line bidon subifs parentif]} then {
	hp-ajouter-iface t $idx $parentif

	set lsubif [parse-list $subifs yes]
	foreach subif $lsubif {
	    set error [hp-set-ifattr t $subif parentif $parentif]
	    if {$error} then {
		break
	    }
	    hp-ajouter-iface t $idx $subif
	}
    } else {
	warning "Invalid trunk specification ($line)"
	set error 1
    }

    return $error
}

#
# Entr�e :
#   - line = <communaute> <blah blah>
#   - idx = eq!<eqname>
# Remplit :
#   - tab(eq!<nom eq>!snmp) {<communaute> ...}
#
# Historique
#   2006/01/06 : pda/jean : conception
#

proc hp-parse-snmp-community {active line tab idx} {
    upvar $tab t

    if {[regexp {^\s*"(\S+)"\s*(.*)$} $line bidon comm reste]} then {
	lappend t($idx!snmp) $comm
	set error 0
    } else {
	warning "Inconsistent SNMP community string ($line)"
	set error 1
    }
    return $error
}

#
# Entr�e :
#   - line = <iflist>
#   - idx = eq!<eqname>
#   - tab(eq!<nom eq>!context) "vlan"
#   - tab(eq!<nom eq>!lvlan!lastid) <id>   (si context = "vlan")
# Remplit
#   - tab(eq!<nom eq>!if!<ifname>!link!type) <ether/trunk>
#   - tab(eq!<nom eq>!if!<ifname>!link!vlans) {vlanid...}
#
# Historique
#   2008/07/21 : pda/jean : conception
#

proc hp-parse-untagged {active line tab idx} {
    upvar $tab t

    set error 0

    if {$active} then {
	set vlanid $t($idx!lvlan!lastid)
	set liface [parse-list $line yes]
	foreach iface $liface {
	    set error [hp-set-ifattr t $iface "type" "ether"]
	    if {$error} then {
		break
	    }
	    set error [hp-set-ifattr t $iface "vlan" $vlanid]
	    if {$error} then {
		break
	    }
	    hp-ajouter-iface t $idx $iface
	}
    }

    return $error
}

proc hp-parse-tagged {active line tab idx} {
    upvar $tab t

    set error 0

    if {$active} then {
	set vlanid $t($idx!lvlan!lastid)
	set liface [parse-list $line yes]
	foreach iface $liface {
	    set error [hp-set-ifattr t $iface "type" "trunk"]
	    if {$error} then {
		break
	    }
	    set error [hp-set-ifattr t $iface "vlan" $vlanid]
	    if {$error} then {
		break
	    }
	    hp-ajouter-iface t $idx $iface
	}
    }

    return $error
}


###############################################################################
# Attributs d'une interface
###############################################################################

#
# Sp�cifie les attributs d'une interface
#
# Entr�e :
#   - tab : nom du tableau
#   - idx : index (jusqu'au nom de l'interface : "eq!<nom eq>!if!<ifname>")
#   - attr : name, stat, type, ifname, vlan, allowed-vlans
#   - val : valeur de l'attribut
#
# Sortie :
# - Si lien trunk :
#   - tab(eq!<nom eq>!if!<ifname>!link!type) trunk
#   - tab(eq!<nom eq>!if!<ifname>!link!allowedvlans) {{1 1} {3 13} {15 4094}}
# - Si lien ether :
#   - tab(eq!<nom eq>!if!<ifname>!link!type) ether
#   - tab(eq!<nom eq>!if!<ifname>!link!vlans) {<vlan-id>}    (forc�ment 1 seul)
# - Si lien aggregate : idem trunk ou ether, avec en plus :
#   - tab(eq!<nom eq>!if!<ifname>!link!parentif) <parent-if-name>
#
# Historique
#   2008/07/21 : pda/jean : conception � partir de la version cisco
#

proc hp-set-ifattr {tab idx attr val} {
    upvar $tab t

    set error 0
    switch $attr {
	name {
	    set t($idx!link!name) $val
	}
	stat {
	    set t($idx!link!stat) $val
	}
	desc {
	    set t($idx!link!desc) $val
	}
	type {
	    if {[info exists t($idx!link!type)]} then {
		switch -- "$t($idx!link!type)-$val" {
		    trunk-trunk {
			# rien
		    }
		    ether-trunk {
			set t($idx!link!type) "trunk"
			if {[info exists t($idx!link!vlans)]} then {
			    set ov [lindex $t($idx!link!vlans) 0]
			    set t($idx!link!allowed-vlans) [list $ov $ov]
			    unset t($idx!link!vlans)
			} else {
			    set t($idx!link!allowed-vlans) {}
			}
		    }
		    trunk-ether {
			# rien
		    }
		    ether-ether {
			warning "incoherent 'untagged' vlan for $idx"
		    }
		    default {
			warning "incoherent type for $idx"
		    }
		}
	    } else {
		set t($idx!link!type) $val
		set error 0
	    }
	}
	parentif {
	    set t($idx!link!parentif) $val
	}
	vlan {
	    if {[info exists t($idx!link!type)]} then {
		switch $t($idx!link!type) {
		    trunk {
			lappend t($idx!link!allowed-vlans) [list $val $val]
		    }
		    ether {
			set t($idx!link!vlans) [list $val]
		    }
		    default {
			warning "incoherent type for $idx"
		    }
		}
	    } else {
		warning "Unknown transport-type for $idx"
	    }
	    set error 0
	}
	default {
	    warning "Incorrect attribute type for $idx (internal error)"
	    set error 1
	}
    }
    return $error
}

###############################################################################
# Post-traitement (ou plus exactement, phase pr�alable au post-traitement)
###############################################################################

#
# Traite le tableau avant d'appeler la g�n�ration
#
# Entr�e :
#   - eq : nom de l'�quipement
#   - tab : nom du tableau
#
# Sortie :
# - suppression des interfaces d�sactiv�es
#
# Historique
#   2008/07/24 : pda      : conception
#

proc hp-prepost-process {eq tab} {
    upvar $tab t

    set error 0
    set idx "eq!$eq"

    #
    # Supprimer les interfaces marqu�es comme "disable"
    #

    foreach iface $t($idx!if!disabled) {
	set error [cisco-remove-if t($idx!if) $iface]
    }

    return $error
}