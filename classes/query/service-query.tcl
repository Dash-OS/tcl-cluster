::oo::define ::cluster::service method query { args } {
  set query [lindex $args end]
  set ruid  [lindex $args end-1]
  set args  [lrange $args 0 end-2]
  if { [dict exists $args -timeout] } {
    
  }
  # We send a query payload to the service while also including 
  # a filter so we can be sure only the service we are expecting 
  # will receive the query.
  my send [$CLUSTER query_payload $ruid $query [my sid]]
}