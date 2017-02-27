
::oo::define ::cluster::service {
  variable CLUSTER
  variable UUID PEER PROPS LOCAL HWADDR NAME
  variable LAST_HEARTBEAT AFTER_ID
}

# cluster - a reference to the parent cluster
# descriptor - a dictionary containing a description of this peer.  It will have:
#   uuid      - The peers raw uuid (${hwaddr}@${name}.[join ${protocols} .])
#   peer      - A list container [list $ip $port] taken from [chan configure $chan -peer]
#   name      - The name of the service, taken from the $uuid
#   hwaddr    - The hwaddr of the service, taken from the $uuid
#   protocols - A [list] of protocols taken from the $uuid ([list c t u])
::oo::define ::cluster::service constructor { cluster descriptor } {
  # Save a reference to our parent cluster so that we can communicate it as necessary.
  set CLUSTER $cluster
  # These properties are static and may not be changed or manipulated throughout
  # the lifecycle of a service.  We take them out of the $PROPS and save them directly
  # to our services variables.
  foreach e [list uuid peer hwaddr name] {
    set [string toupper $e] [dict get $descriptor $e]
    dict unset descriptor $e
  }
  
  # Any remaining properties are saved within our services properties.
  set PROPS $descriptor
  
  # Is this peer local to this machine?
  set LOCAL [::cluster::islocal $PEER]
  set AFTER_ID {}
}

::oo::define ::cluster::service destructor {
  after cancel $AFTER_ID
}

# When we receive a heartbeat we will reset the services timeout handler.
# Additionally, if we receive a payload, we will use it to set the settings
# of the service.  
#
# A service will provide a payload with the heartbeat when responding to discovery
# requests and when it wants to broadcast changes to its settings with the cluster.
#
# A service should never EXPECT it's settings will be honored, it is simply a means
# to provide priorities and instructions for how it prefers to be handled.  The only
# hard expectations are set by the available protocols and general configuration it has.
::oo::define ::cluster::service method heartbeat { props } {
  set LAST_HEARTBEAT [clock seconds]
  my SetTimeout
  my MergeProps $props
}

::oo::define ::cluster::service method SetTimeout {} {
  after cancel $AFTER_ID
  set AFTER_ID [after [$CLUSTER ttl] [namespace code [list my Timeout]]]
}

# When our service times out it will destroy itself.  This will occur
# if we do not receive a heartbeat within the TTL Interval provided.
::oo::define ::cluster::service method Timeout {} {
  puts "SERVICE TIMEOUT! $UUID - $LOCAL - $LAST_HEARTBEAT"
  catch { $CLUSTER service_lost [self] }
  [self] destroy
}

# When we want to merge new props with our service this method will handle
# merging of each prop and handling any changes that may be required based
# on the prop being changed.
#
# This will only occur once a service passes the content security protection
# placed on the service / cluster.
::oo::define ::cluster::service method MergeProps { props } {
  if { $props eq {} } { return }
  dict for {k v} $props {
    if { [ my PropChanges $k $v ] } {
      dict set PROPS $k $v
    }
  }
}

# When a prop is changing we call this method to determine if any actions should
# take place due to the changes being made.  If we return 0 then the changes will
# be refused, otherwise the changes will be made once our evaluation completes.
#
# We can access the previous / current values by simply capturing $PROPS current value.
#
::oo::define ::cluster::service method PropChanges { prop nval } {
  if { [dict exists $PROPS $prop] } { set pval [dict get $PROPS $prop] }
  puts "Service Prop Changing: $prop ---> $nval"
  dict set PROPS $prop $nval
  return 1
}

# When we want to send a message to a service, we need to determine what the
# best way to establish a communication channel may be.  We do this by using 
# the properties of the service, the protocols it supports, and the protocols
# that we support.
#
# If the protocols property is provided, we will attempt each given protocol in the
# given order.  If it is empty, we will use all the protocols that this service supports
# in the order they are defined by the service.
#
# When automatically determining the protocols to try:
# $protocols will be in the order given by the services $uuid.  We will attempt
# each that our local $CLUSTER supports until we reach the "cluster" protocol (c)
# which we automatically must assume worked.  We will never attempt to send to
# any protocol listed after our cluster protocol unless it is explicitly defined
# within the send method.
#
# If $skip is defined, we expect it is a list of protocols that should not be attempted.
::oo::define ::cluster::service method send { op {ruid {}} {data {}} {protocols {}} {skip {}} } {
  if { $protocols eq {} } { set protocols [dict get $PROPS protocols] }
  if { $ruid ne {} } { append op $ruid }
  foreach protocol $protocols {
    # Should we skip this protocol?
    if { $protocol in $skip } { continue }
    # We attempt to send to each protocol defined.  If our send returns true, we
    # expect the send was successful and return the protocol that was used for the
    # communication.
    #
    # We include a reference to the protocol to ourselves so it can query any
    # information necessary to complete the request.
    if { [$CLUSTER send $protocol $op $data [self]] } { 
      puts "Sent to Service: $protocol $op $data | [self]"
      return $protocol 
    }
  }
  # If none of the attempted protocols were successful, we return an empty value
  # to the caller.
  puts "Failed to Send to Service: [self] via $protocols - $op $data"
  return
}

# This method is called to get a list of properties that we want to be able to 
# resolve with.
::oo::define ::cluster::service method resolver {} {
  return [list $NAME $HWADDR $UUID [lindex $PEER 0] {*}$[dict get $PROPS protocols]]
}

# When we receive a payload from what appears to be the service, we will validate
# against the service to determine if we should accept the payload or not.  We
# return true/false based on the result.
::oo::define ::cluster::service method validate { descriptor } {
  set peer [dict get $descriptor peer]
  if { $peer ne $PEER } {
    if { [string equal [lindex $PEER 0] [lindex $peer 0]] } {
      # We want to confirm that the message is received from the 
      # same peer IP that this service was created as.
      #
      # TODO: Use other methods so that the IP of the service can
      #       change due to DHCP / restarts / etc.
      return 1
    } else { return 0 }
  } else { return 1 }
}

# Our objects accessors
::oo::define ::cluster::service method ip     {} { lindex $PEER 0 }
::oo::define ::cluster::service method props  {} { return $PROPS  }
::oo::define ::cluster::service method uuid   {} { return $UUID   }
::oo::define ::cluster::service method peer   {} { return $PEER   }
::oo::define ::cluster::service method local  {} { return $LOCAL  }
::oo::define ::cluster::service method name   {} { return $NAME   }
::oo::define ::cluster::service method hwaddr {} { return $HWADDR }
::oo::define ::cluster::service method proto_props { protocol } {
  if { [dict exists $PROPS $protocol] } { return [dict get $PROPS $protocol] }
}