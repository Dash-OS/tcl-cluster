# When a service believes another service is no longer responding, it will report
# it to the cluster.  We will await any other reports from other services and combine
# them into our request.  This way if we end up losing a group of services within a 
# short period we do not spam the cluster with tons of pings.
::oo::define ::cluster::cluster method schedule_service_ping { service_id } {
  my variable SERVICES_TO_PING
  if { [info exists SERVICES_TO_PING] } {
    # We are already expecting to ping, add our service to the group if it does
    # not already exist.
    if { $service_id ni [dict get $SERVICES_TO_PING services] } { 
      dict lappend SERVICES_TO_PING services $service_id
    }
  } else { 
    dict set SERVICES_TO_PING services $service_id
    dict set SERVICES_TO_PING after_id [after 5000 [namespace code [list my send_service_ping]]]
  }
}

::oo::define ::cluster::cluster method send_service_ping {} {
  my variable SERVICES_TO_PING
  if { ! [info exists SERVICES_TO_PING] } { return }
  set services [dict get $SERVICES_TO_PING services]
  if { $services ne {} } {
    # Broadcast our ping request to the cluster
    my broadcast [my ping_payload $services]
    my expect_services $services
  }
  
  unset SERVICES_TO_PING
}

::oo::define ::cluster::cluster method cancel_service_ping { service_id } {
  my variable SERVICES_TO_PING
  if { ! [info exists SERVICES_TO_PING] } { return }
  set services [dict get $SERVICES_TO_PING services]
  set services [lsearch -all -inline -not -exact $services $service_id]
  if { $services eq {} } {
    # We heard back from all services, cancel the ping request
    after cancel [dict get $SERVICES_TO_PING after_id]
    unset SERVICES_TO_PING
  }
}

# When a ping is sent to the cluster by a service it indicates that another
# service has likely had problems communicating with it and thinks we may
# need to remove a member from the cluster.  
#
# We need to check if we are included in the list of services (and send a ping if so)
# and also setup an event which will reduce the services TTL across the cluster.  If 
# the service is still alive, it should send its heartbeat to the cluster within the 
# next 15 seconds.  In addition, if more than one service is listed in the request,
# the service should send at a random time between immediate and 15 seconds so that
# we do not flood the cluster with responses.
::oo::define ::cluster::cluster method expect_services { services } {
  if { $SERVICE_ID in $services } {
    # Uh-Oh!  We are being pinged!  Should we respond immediately or stagger?
    if { [llength $services] < 2 } {
      # Include our protoprops with the heartbeat in case the member
      # has old or invalid values. Also send our tags
      my heartbeat [list protoprops] 1
    } else {
      # Since more than 2 services are being pinged, we will stagger our response
      # a bit.
      set timeout [::cluster::rand 0 15000]
      after cancel $AFTER_ID
      set AFTER_ID [ after $timeout [namespace code [list my heartbeat [list protoprops] 1]] ]
    }
    # Remove ourself from the list of services.  If any remain, treat them like normal.
    set services [lsearch -all -inline -not -exact $services $SERVICE_ID]
  }
  if { $services ne {} } {
    set known_services [my services]
    foreach service_id $services {
      set service [lsearch -inline -glob $known_services *${service_id}*]
      if { $service ne {} } {
        # We found the service being pinged, we will reduce its TTL so that it must report
        # to the cluster within the next 20 seconds or it will be removed from this member.
        $service expected 20
      }
    }
  }
  # Schedule a service check after 30 seconds 
  my ScheduleServiceCheck
}
