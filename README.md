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

> **Note:** All of the platform-specific functionality is implemented in [utils/platform.tcl](https://github.com/Dash-OS/cluster-comm/blob/master/utils/platform.tcl). 

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

#### Lightweight Binary Wire Protocol

In order to make the cluster communication as fast and light-weight as possible, a special 
binary wire protocol is utilized (bpacket) which resembles [Protocol Buffers](https://developers.google.com/protocol-buffers/) 
which a few modifications.  In general this should be anywhere from 30-60% smaller than using JSON or 
similar (depending on the type of packet being sent).

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

#### Protocol Self-Healing

Part of the `cluster` protocol provides capabilities for services to assist each other in 
self-healing when something goes wrong with one of a services preferred protocol handlers 
without its knowledge.

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
## Channels / Hooks / Encryption

Channels provide an additional layer of extensibility to your cluster communications. 
Members of the cluster will ignore any data they receive that are on channels they have 
not subscribed to. 

When combined with hooks this provides us with the capability to add some simple add-ons 
to how our cluster will work. 

For example, say we wanted to encrypt some of the data that was being transmitted, but only 
on a specific channel.  This way only members which know the encryption key would attempt to 
read it. 

All we would need to do is add a hook for the channel we want which would encrypt before sending 
and decrypt before reading.  The encrypted key of a payload tells us to save raw bytes rather than 
utf-8 encoded strings.

```tcl
$cluster hook channel 5 send {
  if { [dict exists $payload data] } {
    dict set payload encrypted [encrypt [dict get $payload data]]
    dict unset payload data
  }
}

$cluster hook channel 5 receive {
  dict set payload data [decrypt [dict get $payload encrypted]]
  dict unset payload encrypted
}
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

## `cluster` API Reference 

The top-level API is used to join a given cluster.

#### cluster join *?..configuration?*
 
All of the configuration options are optional.  It is valid to simply call cluster join 
to utilize the default values. 

| Argument Name     |  Type   |  Required  |  Default  |  Description   |
| ------------- | ------  | ---------- | --------- | -------------- |
| -address      | IP      | No         | 230.230.230.230 | The Broadcast IP Address to use for the cluster    |
| -port         | Port    | No         | 23000           | The Broadcast Port to use for the cluster |
| -ttl          | Seconds | No         | 600             | How many seconds should a service live if unseen? |
| -heartbeat    | MS      | No         | 120000          | At what interval should we send heartbeats to the cluster? |
| -channels     | List    | No         | 0 1 2           | A list of communication channels that we should join |
| -remote       | Integer | No         | 0               | Should we listen outside of localhost? TTL. |
| -tags         | List    | No         |                 | A list of tags that we want to broadcast to the cluster. |
| -protocols    | List    | No         | t c             | What protocols do we want to support for this member?  |
| -$proto_id    | Dict    | Yes*       |                 | This is only required when providing custom protocols. |

> More Information on each argument coming soon...

---

## `$cluster` Commands Reference

Once we have joined the cluster, we will use the reference that was returned to coordinate 
communication and requests.

#### $cluster heartbeat *?props tags channel?*

Send a heartbeat to the cluster, informing them of your presence on the cluster.  This is 
handled automatically but can be sent manually if desired.  We have a few optional arguments 
that may be included.

---

#### $cluster discover

Send a discovery probe to the cluster.  This requests that all members of the cluster 
report to you.  Services may report back at randomly delayed intervals. For the most part 
this should never really be required as it is handled internally.

---

#### $cluster broadcast

This command allows you to broadcast a command to all members of the cluster.  It 
expects a single argument (*payload*) which should be a properly formatted payload 
dict.

---

#### $cluster send *...args*

> More Information Coming Soon...

---

#### $cluster query *...args*

 - **-id**
 - **-collect** 
 - **-resolve**
 - **-command**
 - **-query**
 - **-timeout**

---

#### $cluster resolve 

This allows us to "search" for matching services which meet a specific criteria.  This 
is used to aid in sending queries and events to the cluster.

---

#### $cluster resolver

A more advanced version of resolve which allows us to add additional logic to the 
resolution process.

---

#### $cluster resolve_self

> More Information Coming Soon...

---

#### $cluster tags *?modifier ...tags?* *?modifier ...tags?*

When sent without arguments, this will respond with the current tags that have been 
sent to the members of the cluster.  Otherwise we can use this command to add, remove, 
or replace the tags that we wish to associate ourselves with.  

When tags are modified, they will be included on the next heartbeat which is sent to the 
cluster.  Other than that, they are not included unless requested through discovery or 
direct queries.

Think of tags as a way of determining which members of the cluster are in various states 
and/or provide various services.

The command itself provides a syntax for modifying the current tags where each argument is 
taken and handled in the order given.  Modifiers allow us to conduct various operations on the 
tags so that we can easily manipulate them if needed.

> **Note:** tags are what we are generally using while resolving services during send and query operations.

##### Tag Modifiers

| Modifier                  |  Description   
|--------------------------|-------------- 
| **`-map`**                |  Similar to `[string map]`, this will replace a given tag with another if it exists.  
| **`-mappend`**            |  Similar to `-map` except that it will add the second tag even if the first does not exist.  It will also only add the new tag if it does not already exist.
| **`-remove`**             |  Removes the given tags if they exist.
| **`-replace`**            |  Replaces the entire list of tags with the given tags then switches back to append for any further arguments given. 
| **`-append`** (Default)   |  (-lappend is synonymous), adds the given tag to the list of tags. 

```tcl

$cluster tags tag0 tag1
#  tag0 tag1

$cluster tags -append tag0 tag2 -map [list tag2 tag3] -remove tag3 -append tag4 tag5
#  tag0 tag1 tag4 tag5

# In this example the -map does nothing since tag10 does not exist in our list of tags.
$cluster tags -map [list tag10 tag12]
#  tag0 tag1 tag4 tag5

$cluster tags -mappend [list tag0 tag5] [list tag6 tag8] [list tag3 tag8]
#  tag1 tag4 tag5 tag8

```

> **Tip:** You can think of `[-mappend]` as a shortcut for `[$cluster tags -remove tag1 -append tag2]`

---

#### $cluster services

Returns a list of references to each service that we currently know about.

---

#### $cluster known_services

Returns the number of services we currently know about.

---

#### $cluster config

Returns the current configuration object that our cluster and services utilize 
to coordinate their lifecycles.

---

#### $cluster ttl

Returns the current time-to-live value that is used.  This determines how long we will 
allow a discovered service to remain in memory before removing it (if we have not received 
a heartbeat or communication from it).

> There are times this value is reduced.  When we attempt to open a channel with a service and it 
> fails for any reason, we will dispatch a "ping" request.  This will tell our cluster that we have 
> failed to communicate with a service.  All services will then expect a heartbeat or they will remove 
> that service on their next evaluation.

---

#### $cluster uuid

> More Information Coming Soon...

---

#### $cluster hook

> More Information Coming Soon...

---

## `$service` Commands Reference

#### $service resolve

> More Information Coming Soon...

---

#### $service resolver

```tcl

# resolver is a more powerful option than resolve which allows adding of some added logic.
# Each argument will define which services we want to match against.
#
# Additionally, we can specify boolean-type modifiers which will change the behavior.  These
# are applied IN ORDER so for example if we run -match after -has then has will not use match
# but any queries after will.
#
# Modifiers:
#  -equal (default)
#   Items will use equality to test for success
#  -match 
#   Items will use string match to test for success
#  -regexp
#   Items will use regexp to test for success on each item

# -has [list]
#   The service must match all items in the list
# -not [list]
#   The service must NOT match any of the items given
# -exact [list]
#   The service must have every item in the list and no others
# -some [list]
#   The service must match at least one item in the list
#
# Examples:

set services [ $cluster resolver -match -has [list *wait] -equal -some [list one two three] ]

```

> More Information Coming Soon...

---

#### $service query

> More Information Coming Soon...

---

#### $service send

> More Information Coming Soon...

---

#### $service info

> More Information Coming Soon...

---

#### $service ip

> More Information Coming Soon...

---

#### $service props

> More Information Coming Soon...

---

#### $service tags

> More Information Coming Soon...

---

#### $service local

> More Information Coming Soon...

---

#### $service hid

> More Information Coming Soon...

---

#### $service sid

> More Information Coming Soon...

---

#### $service last_seen

> More Information Coming Soon...

---

#### $service proto_props

> More Information Coming Soon...

---

## Hooks

Hooks provide a means to customize the evaluation environment with ***short snippets of 
mutations and additions*** to the regular lifecycle of the package.  Hooks are always 
evaluated within the hooks given context.  

We can modify the behavior at each level by either changing values before they are sent 
or received, or throwing an error to cancel any further handling.

### Transmission Hooks

#### `$cluster hook evaluate receive`

#### `$cluster hook evaluate send`

#### `$cluster hook event`

### Channel Hooks

#### `$cluster hook channel receive <channels>`

#### `$cluster hook channel send <channels>`

### Query Hooks 

#### `$cluster hook query`

### Protocol Hooks

#### `$cluster hook protocol <proto> receive`

#### `$cluster hook protocol <proto> send`

### Service Hooks

#### `$cluster hook service evaluate`

#### `$cluster hook service validate`

#### `$cluster hook service discovered`

#### `$cluster hook service lost`