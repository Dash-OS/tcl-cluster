
# Each service that is discovered will have an object created which manages
# its lifecycle.
::oo::define ::cluster::service {
  variable CLUSTER UUID CHANNELS
  variable LAST_HEARTBEAT PROPS
  variable PROTOCOLS FLAGS SERVICE_ID SYSTEM_ID
  variable SOCKETS ADDRESS TAGS LOCAL RESOLVER
  variable NEW
}

::oo::define ::cluster::service constructor { cluster proto chanID payload descriptor } {
  # Save a reference to our parent cluster so that we can communicate with it as necessary.
  set CLUSTER $cluster
  # PROPS stores the services properties.  This will include things such as
  # "tags", "protocol properties", etc.  They are provided via heartbeat and/or
  # discovery requests.  When props are received, they are merged into the previous
  # properties unless we receive a FLUSH request (7).
  set PROPS [dict create]

  set SERVICE_ID [dict get $payload sid]
  set SYSTEM_ID  [dict get $payload hid]
  set CHANNELS   [list 0]
  set PROTOCOLS  [dict get $payload protocols]
  set SOCKETS    [dict create]
  set TAGS       [list]
  set ADDRESS    [dict get $descriptor address]
  set NEW        1
  if { [dict exists $descriptor local] } {
    set LOCAL [dict get $descriptor local]
    # If we are local then we need to set ADDRESS to our
    # own IP.
    set ADDRESS 127.0.0.1
  } else {
    set LOCAL [$CLUSTER is_local $ADDRESS]
  }
  my SetResolve
  # Confirm that we can validate this service using our standard validate method.  This is called
  # directly by the cluster before parsing any payload after we have been created initially.
  if { ! [my validate $proto $chanID $payload $descriptor] } {
    throw error "Failed to Validate Discovered Service"
  }
}

::oo::define ::cluster::service destructor {
  # Cleanup any sockets which have been opened for this service.
  try {
    dict for { protocol chanID } $SOCKETS {
      set proto [$CLUSTER protocol $protocol]
      $proto done [self] $chanID 0
    }
    # Report the service being lost to the cluster
    $CLUSTER event service lost [self]
  } on error {result options} {
    ::onError $result $options "While Removing a Cluster Service"
  }
}

::oo::define ::cluster::service method SetResolve {} {
  set RESOLVER [list {*}$TAGS [my hid] [my sid] [my ip]]
  if {[my local]} {
    lappend RESOLVER "localhost"
  }
}

# Not for hooks that must be mutated.
::oo::define ::cluster::service method hook { payload args } {
  set service [self]
  set cluster $CLUSTER
  return [$CLUSTER run_hook {*}$args]
}

# When we determine a service may no longer exist on the cluster, but did not
# exit gracefully, this will be called on the service.  This means that the
# service has been requested to report itself to the cluster or else it will
# be removed from the cluster.
::oo::define ::cluster::service method expected { {within 30} } {
  my variable SERVICE_EXPECTED
  if {[my last_seen] < 3 || [info exists SERVICE_EXPECTED]} {
    # If the service was last seen within the last 3 seconds, we will ignore this.
    return 0
  }
  set SERVICE_EXPECTED 1
  set NEW_HEARTBEAT [expr {[clock seconds] - [$CLUSTER ttl] + $within}]
  if {$NEW_HEARTBEAT < $LAST_HEARTBEAT} {
    set LAST_HEARTBEAT $NEW_HEARTBEAT
  }
  return 1
}
