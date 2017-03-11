::oo::define ::cluster::cluster method QueryID {} {
  return [format {q%s%s#%s} \
    [string index $SERVICE_ID 0] \
    [string index $SERVICE_ID 2] \
    [string index $SERVICE_ID end] \
    [::cluster::query_id]
  ]
}

::oo::define ::cluster::cluster method query { args } {
  if { {-collect} in $args } {
    set args [lsearch -all -inline -not -exact $args {-collect}]
    dict set args -collect 1
  }
  if { [dict exists $args -id] } {
    set qid [dict get $args -id] 
  } else { 
    set qid [my QueryID] 
    dict set args -id $qid
  }
  
  set query ${NS}::queries::$qid
  if { [info commands $query] ne {} } {
    # When we have a query which matches a previously created query
    # that has not yet timed out we will force it to finish first.
    $query destroy
  }
  
  try {
    set query [::cluster::query create $query [self] {*}$args]
  } trap NO_SERVICES {result} {
    return
  } on error {result options} {
    ~ "QUERY CREATION ERROR: $result"
    return
  }
  
  dict set QUERIES $qid $query
  
  return $query
}

# Called by a service when it wants to provide a response to a query object.
::oo::define ::cluster::cluster method query_response { service payload } {
  if { [dict exists $payload ruid] } {
    set ruid [dict get $payload ruid]
    if { [dict exists $QUERIES $ruid] && [info commands [dict get $QUERIES $ruid]] ne {} } {
      try {
        return [ [dict get $QUERIES $ruid] event response $service $payload ] 
      } on error {result} {
        #puts "QUERY REQUEST ERROR: $result"
        return 0
      }
    } else { return 0 }
  } else { return 0 }
}

::oo::define ::cluster::cluster method query_done { qid } {
  if { [dict exists $QUERIES $qid] } { dict unset QUERIES $qid }
}