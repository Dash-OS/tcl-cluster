# tcl cluster

**UNFINISHED (But Working)**

`cluster` is a tcl package which provides a simple light-weight framework for
providing inter-process and inter-machine discovery and communications.  

`cluster`'s evaluation hooks provide powerful extensibility, allowing the programmer to modify 
the general behavior of a cluster to fit their security and/or communications handling needs.

**Package Dependencies**

- [TclUDP](https://sourceforge.net/projects/tcludp/) Extension (v1.0.11 or higher)

**Supported Platforms**

- Linux / Unix
  - Requires [tuapi](http://chiselapp.com/user/rkeene/repository/tuapi/home)

It is actually relatively easy to support other platforms or not require tuapi.  Just need
to modify a few of the initial procs to give data such as LAN IP's and MAC Address.

## Key Concepts

`cluster` aims to provide a lightweight modular framework for cluster discovery, communications, 
and coordination.  `cluster` members automatically discover each other and provide their preferred 
protocols for communication.  

In a local environment, it's as simple as having both run `[cluster join]` and awaiting 
discovery.  We can then pass messages and commands between our cluster members.

#### Local and/or Remote Capable

By default, our beacons will be set with a UDP TTL of 0.  This means that our beacons 
will only be heard locally on the system.  We may set the ttl value used by our beacons 
using the `-remote` configuration parameter.  Anything higher than 0 will begin to open
our beacons further out from the machine.

When `-remote` is set to 0, communications will be ignored from any communications originating 
from outside of our localhost.  You may also use hooks to provide this type of security based on 
the context of the cluster.

#### Customizable & Extendable

`cluster` provides hooks that allow you each member to intercept evaluation at different 
parts of the communications process.  This allows you to add security, new features, and/or 
run tasks whenever needed.  We do not automatically execute any code within your interp, it is 
up to you to add such functionality if needed (examples below).

#### Reliable Multi-Protocol Negotiation

Each member in the cluster advertises what protocols it knows how to use as well as the priority 
of those protocols. Other members use this to establish direct channels of communication when needed. 
Should a protocol fail for any reason, the next will be attempted (and so on).

#### Custom Protocol Handlers

It is extremely easy to provide new protocols that cluster can utilize.  Simply follow the 
general template provided by the included protocols.  Out of the box we support [UDP](https://sourceforge.net/projects/tcludp/), 
[TCP](https://www.tcl.tk/man/tcl8.6/TclCmd/socket.htm), and [Unix Sockets](https://sourceforge.net/projects/tcl-unixsockets/).  

## Simple Service Discovery

Below we see a simple example of using `cluster` where we simply join the cluster
and register a hook to inform us whenever a new service has been discovered.

Running this on two different shells (on the same system for now), you should
see the two shells discovered each other.  In each example, the `$service` variable 
is a reference to the service object which can be used to communicate with or get 
further context about the service.

```tcl

package require cluster
set cluster [cluster join -tags [list service_one]]

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```

```tcl

package require cluster
set cluster [cluster join -tags [list service_two]]

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```

## Queries

Queries allow us to send a command to the cluster and collect the results.  They 
provide a special object that lives for a short period to coordinate the responses 
automatically for you.
 
```tcl

package require cluster
set cluster [cluster join -tags [list service_one]]

set var "Hello,"

$cluster hook query {
  if { ! [my local] } { throw error "Only Local can Query" }
  uplevel #0 [list try $data]
}

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```

```tcl

package require cluster
set cluster [cluster join -tags [list service_two]]

set var "World!"

$cluster hook query {
  if { ! [my local] } { throw error "Only Local can Query" }
  uplevel #0 [list try $data]
}

$cluster hook service discovered {
  puts "New Service Discovered: $service"
}

# Enter the event loop and allow cluster to work
vwait _forever_

```

```tcl

package require cluster
set cluster [cluster join -tags [list service_three]]

# Our QueryResponse will be called with events that occur during
# the queries lifecycle.
proc QueryResponse { event } {
  lassign $event action query
  switch -- $action {
    response {
      # A Service has provided a response.  Return the result so 
      # we can collect the results when completed.
      return [$query result]
    }
    done {
      # Our query is complete - all services have responded.
      set results [$query results]
      puts "Query Completed!  Results Are:"
      # Hello, World!
      puts [dict values $results]
    }
    timeout {
      # Our query has timed out
    }
  }
}

proc RunQuery {} {
  # Query all the services on the localhost, collect the results, run QueryEvent 
  # for events, return the value of ::var
  $::cluster query -collect -resolve localhost -command QueryEvent -query { set ::var }   
}

# Give a few seconds for all the services to join, then run the query
after 5000 RunQuery

# Enter the event loop and allow cluster to work
vwait _forever_

```

## Commands Reference

### `$cluster`

#### `$cluster heartbeat`

#### `$cluster discover`

#### `$cluster broadcast`

#### `$cluster send`

#### `$cluster query`

 - **-id**
 - **-collect** 
 - **-resolve**
 - **-command**
 - **-query**
 - **-timeout**

#### `$cluster resolve`

#### `$cluster resolver`

#### `$cluster resolve_self`

#### `$cluster tags`

#### `$cluster flags`

#### `$cluster services`

#### `$cluster known_services`

#### `$cluster config`

#### `$cluster ttl`

#### `$cluster uuid`

#### `$cluster hook`

### `$service`

#### `$service resolve`

#### `$service resolver`

#### `$service query`

#### `$service send`

#### `$service info`

#### `$service ip`

#### `$service props`

#### `$service tags`

#### `$service local`

#### `$service hid`

#### `$service sid`

#### `$service last_seen`

#### `$service proto_props`

## Hooks

Hooks provide a means to customize the evaluation environment with ***short snippets of 
mutations and additions*** to the regular lifecycle of the package.  Hooks are always 
evaluated within the hooks given context.  

We can modify the behavior at each level by either changing values before they are sent 
or received, or throwing an error to cancel any further handling.


#### `$cluster hook evaluate send`

#### `$cluster hook evaluate receive`

### Channel Hooks

#### `$cluster hook channel receive <channels>`

### Evaluate Hooks

#### `$cluster hook evaluate service`

#### `$cluster hook evaluate receive`

#### `$cluster hook evaluate send`

> Called right after the 

### Protocol Hooks

#### `$cluster hook protocol <proto> receive`

#### `$cluster hook protocol <proto> send`

### Op Hooks

#### `$cluster hook op <op> receive`

#### `$cluster hook op <op> send`

### Service Hooks

#### `$cluster hook service eval`

#### `$cluster hook service validate`

#### `$cluster hook service found`

#### `$cluster hook service lost`


# cluster-comm
# cluster-comm
