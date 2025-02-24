;; Autonomous Bike Courier Simulation
;; A multi-agent simulation modeling food delivery couriers with varying levels
;; of autonomy and cooperation. The model explores how different decision-making
;; strategies affect overall system efficiency.

;; Future Development Note:
;; In future versions, committed jobs may be canceled/handed-over/stolen
;; while moving towards the restaurant (pick-up location)

extensions [table]  ;; Using table extension for efficient key-value storage

;; Define agent types (breeds)
breed [ jobs job]               ;; Delivery orders that need to be fulfilled
breed [ couriers courier ]      ;; Courier agents that perform deliveries
breed [ customers customer]     ;; Destination points for deliveries
breed [ clusters cluster]       ;; Centers of restaurant groupings
breed [ restaurants restaurant] ;; Order origin points

;; Patch (grid cell) properties
patches-own[
  restaurant-cluster?    ;; Boolean: true if patch is part of a restaurant cluster
  cluster-no             ;; Identifier for the cluster this patch belongs to
]

;; Restaurant cluster properties
clusters-own[
  ;; Currently empty, reserved for future expansion
]

;; Restaurant properties
restaurants-own[
  cluster-number        ;; Which cluster this restaurant belongs to
  restaurant-id         ;; Unique identifier for this restaurant
]

;; Delivery job properties
jobs-own [
  tick-number         ;; When the job was created
  job-number          ;; Unique identifier for job
  origin              ;; Starting location (restaurant)
  destination         ;; Delivery location (customer)
  available?          ;; Whether job can be picked up
  cluster-location    ;; Which restaurant cluster this belongs to
  reward              ;; Payment for completing delivery
  restaurant-id       ;; ID of originating restaurant
]

;; Courier properties
couriers-own [
  current-job          ;; Currently assigned delivery task
  next-location        ;; Where the courier is heading
  current-cluster-location ;; Current cluster area
  status              ;; Current state: on-job (red), waiting (orange),
                      ;; searching (green), moving-towards-restaurant (blue)
  to-origin?          ;; Whether moving to pickup location
  to-destination?     ;; Whether moving to delivery location
  total-reward        ;; Cumulative earnings
  reward-list         ;; History of rewards
  reward-list-per-restaurant ;; Table tracking performance at each restaurant
  current-highest-reward    ;; Best available reward after memory fade
  current-best-restaurant   ;; Restaurant with highest expected reward
  jobs-performed      ;; List of completed delivery locations
]

;; Customer properties
customers-own[
  current-job        ;; Associated delivery job
  tick-of-order      ;; When order was placed
  reward             ;; Payment offered for delivery
]

;; Global variables
globals [
  ;; These are defined as sliders in the interface:
  ;autonomy-level        ;; 1 = low, 2 = medium, 3 = high
  ;cooperativeness-level ;; 1 = low, 2 = medium, 3 = high

  job-no                  ;; Counter for unique job IDs
  on-the-fly-jobs         ;; Jobs taken while searching
  memory-jobs             ;; Jobs taken based on memory
  free-moving-threshold   ;; When to switch to free movement
  current-restaurant      ;; Current restaurant being processed
  waiting-couriers        ;; Count of waiting couriers
  returning-couriers      ;; Count of returning couriers
  delivering-couriers     ;; Count of actively delivering
  searching-couriers      ;; Count of searching couriers

  show-cluster-lines?     ;; Boolean to toggle line visibility
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                SETUP PROCEDURES                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the simulation
to setup
  clear-all
  reset-ticks
  set show-cluster-lines? true ;; Set default to true, can be controlled via interface
  setup-restaurant-clusters    ;; Create restaurant groups
  setup-couriers               ;; Initialize courier agents

  ;; After creating restaurants and clusters, draw the connecting lines
  if show-cluster-lines? [
    draw-cluster-lines
  ]

  ;; Reset global counters
  set job-no 0
  set on-the-fly-jobs 0
  set memory-jobs 0
  set free-moving-threshold 1
  set waiting-couriers 0
  set returning-couriers 0
  set delivering-couriers 0
  set searching-couriers 0
end

;; Procedure to draw lines between clusters and their restaurants
to draw-cluster-lines
  ;; Clear any existing lines first
  ask links [die]

  ;; For each restaurant, create a link to its cluster
  ask restaurants [
    ;; Find the restaurant's cluster
    let my-cluster one-of clusters with [who = [cluster-number] of myself]

    ;; Create a link if the cluster exists
    if my-cluster != nobody [
      create-link-with my-cluster [
        ;; Style the link
        set color yellow - 1  ;; Light yellow
        set thickness 0.25
        set shape "default"  ;; Straight line
      ]
    ]
  ]
end

;; Add a command to toggle line visibility
to toggle-cluster-lines
  set show-cluster-lines? not show-cluster-lines?

  ifelse show-cluster-lines? [
    draw-cluster-lines
  ][
    ask links [die]  ;; Remove all lines
  ]
end

;; Create and initialize courier agents
to setup-couriers
  set-default-shape turtles "bug"

  ;; Create list of all restaurants
  let restaurant-list []
  ask restaurants [
    set restaurant-list insert-item 0 restaurant-list self
  ]

  let i 1

  ;; Create each courier
  loop [
    let courier-xcor 0
    let courier-ycor 0
    let cur-status ""
    let cur-color grey

    ;; Place courier either randomly or at a restaurant
    ifelse random-startingpoint-couriers [
      ;; Random starting position
      set courier-xcor random-xcor
      set courier-ycor random-ycor
      set cur-status "searching-for-next-job"
      set cur-color green
    ][
      let temp-restaurant item 0 restaurant-list
      set courier-xcor [xcor] of temp-restaurant
      set courier-ycor [ycor] of temp-restaurant
      set cur-status "waiting-for-next-job"
      set cur-color orange
    ]

    ;; Create the courier agent
    create-couriers 1 [
      set size 2
      setxy courier-xcor courier-ycor
      set status cur-status
      set color cur-color
      set waiting-couriers waiting-couriers + 1
      set current-job nobody
      set next-location nobody
      set jobs-performed []

      ;; Initialize reward tracking
      let total-restaurants restaurant-clusters * restaurants-per-cluster
      set reward-list n-values total-restaurants [0]
      create-reward-tables
      set current-highest-reward 0
    ]

    ;; Rotate through restaurant list for initial placement
    set restaurant-list but-first restaurant-list
    if empty? restaurant-list [
      ask restaurants [
        set restaurant-list insert-item 0 restaurant-list self
      ]
    ]

    ;; Stop when we've created all couriers
    if i = courier-population [
      show "Couriers setup completed"
      stop
    ]
    set i i + 1
  ]
end

;; Initialize reward tracking tables for a courier
to create-reward-tables
  set reward-list-per-restaurant table:make
  let total-restaurants restaurant-clusters * restaurants-per-cluster

  ;; Create entry for each restaurant
  let j 1
  loop [
    let new-list n-values level-of-order [0]
    table:put reward-list-per-restaurant j new-list

    if j = total-restaurants [stop]
    set j j + 1
  ]
end

;; Create and initialize restaurant clusters
to setup-restaurant-clusters
  ;; Reset all patches
  ask patches [set restaurant-cluster? false]
  set current-restaurant 0

  ;; Create cluster centers
  create-clusters restaurant-clusters [
    set shape "flag"
    set size 2
    setxy random-xcor random-ycor
    set color red
  ]

  ;; Create list of clusters
  let cluster-list []
  ask clusters [
    set cluster-list insert-item 0 cluster-list self
  ]

  let i 1

  ;; Create restaurants within each cluster
  loop [
    if empty? cluster-list [stop]

    let cluster-temp item 0 cluster-list
    let patch-list []

    ;; Find valid patches within cluster radius
    ask patches [
      if distancexy [xcor] of cluster-temp [ycor] of cluster-temp < cluster-area-size [
        set restaurant-cluster? true
        set patch-list insert-item 0 patch-list self
      ]
    ]

    ;; Create restaurant at random location in cluster
    set current-restaurant current-restaurant + 1
    let restaurant-patch one-of patch-list
    create-restaurants 1 [
      set shape "house"
      set size 2
      set color white
      set cluster-number [who] of cluster-temp
      set restaurant-id current-restaurant
      setxy [pxcor] of restaurant-patch [pycor] of restaurant-patch
    ]

    set patch-list remove restaurant-patch patch-list

    ;; Move to next cluster when current one is full
    if i = restaurants-per-cluster [
      set cluster-list but-first cluster-list
      set i 0
    ]
    set i i + 1
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                RUNTIME PROCEDURES              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Main simulation loop
to go
  ask couriers [
    ;; Handle cooperative behavior
    if cooperativeness-level > 1 [
      share-information
    ]

    ;; Update decisions based on rewards
    check-rewards

    ;; Execute behavior based on current status
    if status = "searching-for-next-job" [
      wiggle
      check-neighbourhood
    ]
    if status = "waiting-for-next-job" [
      check-neighbourhood
    ]

    ;; Use a single movement handler for all mobile states
    if status = "moving-towards-restaurant" or status = "on-job" [
      ifelse patch-here = next-location [
        ;; We've arrived - handle it in check-on-location
        check-on-location
      ][
        ;; Not yet at destination - try to move there
        if next-location != nobody [
          ;; Calculate proper heading
          face next-location

          ;; Check if we can move in that direction
          ifelse can-move? 1 [
            fd 1
          ][
            ;; Obstacle encountered - try to navigate around
            ifelse random 2 = 0 [
              rt 45
            ][
              lt 45
            ]
            ;; Only move if possible
            if can-move? 1 [
              fd 1
            ]
          ]
        ]
      ]

      ;; High autonomy route evaluation remains for on-job only
      if status = "on-job" and autonomy-level = 3 [
        re-evaluate-route
      ]
    ]

    ;; Handle job handoffs for high cooperation
    if cooperativeness-level = 3 [
      attempt-job-handoff
    ]

    debug-stuck-couriers
  ]

  ;; Create new jobs based on arrival rate
  if job-arrival-rate > random-float 100 [
    create-job
  ]

  ;; Update statistics
  count-courier-activities

  tick
end

;; Share information with nearby couriers (placeholder)
to share-information
end

to debug-stuck-couriers
  let stuck-couriers couriers with [
    color = blue and
    distancexy max-pxcor max-pycor < 5 and
    status = "moving-towards-restaurant"
  ]

  if any? stuck-couriers [
    ask one-of stuck-couriers [
      print (word "Bike " who " is stuck: ")
      print (word "  status: " status)
      print (word "  to-origin?: " to-origin?)
      print (word "  to-destination?: " to-destination?)
      print (word "  next-location: " next-location)
      print (word "  current-job: " current-job)

      if current-job != nobody [
        print (word "  job origin: " [origin] of current-job)
        print (word "  job destination: " [destination] of current-job)
        print (word "  restaurant-id: " [restaurant-id] of current-job)
      ]
    ]
  ]
end

;; Re-evaluate current route (placeholder)
to re-evaluate-route
end

;; Attempt to hand off job to another courier (placeholder)
to attempt-job-handoff
end

;; Random movement behavior
to wiggle
  rt random 40
  lt random 40
  if not can-move? 1 [ rt 180 ]
  fd 1
end

;; Create a new delivery job
to create-job
  let temp-rest one-of restaurants
  let jobxcor [pxcor] of temp-rest
  let jobycor [pycor] of temp-rest

  ;; Generate random customer location
  let custxcor random-xcor
  let custycor random-ycor
  let temp-reward 0
  set job-no job-no + 1

  ;; Create job agent
  create-jobs 1 [
    setxy jobxcor jobycor
    set cluster-location [patch-here] of cluster [cluster-number] of temp-rest
    set restaurant-id [restaurant-id] of temp-rest
    set origin patch-here
    set destination (patch custxcor custycor)
    set shape "house"
    set size 1
    set color green
    set available? true
    set tick-number ticks
    set job-number job-no
    set reward distance destination
  ]

  ;; Create customer agent
  create-customers 1 [
    setxy custxcor custycor
    set shape "person"
    set size 2
    set color cyan
    set current-job job-no
  ]

  ;; Update restaurant color
  ask temp-rest [
    set color orange
  ]
end

;; Check for available jobs in courier's neighborhood
to check-neighbourhood
  if count jobs in-radius neighbourhood-size > 0 [
    let test count jobs
    print (word "Courier:" who "Jobs in radius: " test)
    let temp-job one-of jobs in-radius neighbourhood-size

    ;; Try to take available job
    if [available?] of temp-job [
      print "is available"
      set current-job temp-job
      ask current-job [
        set available? false
      ]

      ;; Set movement target
      set next-location [origin] of current-job
      face next-location

      ;; Update job statistics
      if status = "waiting-for-next-job" [
        set memory-jobs memory-jobs + 1
      ]
      if status = "searching-for-next-job" [
        set on-the-fly-jobs on-the-fly-jobs + 1
      ]

      ;; Update status based on location
      ifelse (distance next-location < 0.5) [  ;; Using a small threshold
        ;; Already at restaurant - go directly to on-job
        set status "on-job"
        set color red
        set to-origin? false
        set to-destination? true
        set next-location [destination] of current-job
        face next-location
      ][
        ;; Need to go to restaurant first
        set status "moving-towards-restaurant"
        set color grey
        set to-origin? true
        set to-destination? false
      ]
    ]
  ]
end

;; Check if courier has reached destination
to check-on-location
  ;; Check for stuck bikes (at edge or unable to move for many ticks)
  if (status = "moving-towards-restaurant" or status = "on-job") and
     next-location != nobody and
     distance next-location < 2 [
    ;; We're very close to destination - consider it arrived
    set xcor [pxcor] of next-location
    set ycor [pycor] of next-location

    ;; Now handle arrival based on status
    if status = "moving-towards-restaurant" [
      ifelse to-origin? [
        ;; At restaurant for pickup
        set to-origin? false
        set status "on-job"
        set color red
        set next-location [destination] of current-job
        set to-destination? true
        face next-location

        ;; Update restaurant appearance
        let temp-rest one-of restaurants with [restaurant-id = [restaurant-id] of [current-job] of myself]
        if temp-rest != nobody [
          ask temp-rest [
            set color white
          ]
        ]
      ][
        ;; Returning to restaurant after delivery
        set status "waiting-for-next-job"
        set color orange
      ]
    ]

    if (status = "on-job") and (to-destination?) and (distance next-location < 0.5) [
      ;; Arrived at customer
      print (word "Courier:" who " arrived at customer " next-location)
      ;set to-destination? false
      ;at-destination
    ]
  ]
end

;; Handle courier arrival at restaurant
to at-origin
  set to-destination? true
  set next-location [destination] of current-job
  face next-location

  ;; Get the restaurant ID from the current job
  let job-restaurant-id [restaurant-id] of current-job

  ;; Try to find the exact restaurant by ID
  let target-restaurant one-of restaurants with [restaurant-id = job-restaurant-id]

  ifelse target-restaurant != nobody [
    ;; Found the correct restaurant
    ask target-restaurant [
      set color white
    ]
  ][
    ;; Alternative: Look for any restaurant on this patch
    let local-restaurants restaurants-on patch-here
    ifelse any? local-restaurants [
      ask local-restaurants [
        set color white
      ]
      ;; Optional debugging information
      print (word "Job " [job-number] of current-job
        " expected restaurant ID " job-restaurant-id
        " but found " count local-restaurants " different restaurants")
    ][
      print (word "Job " [job-number] of current-job
        " references restaurant ID " job-restaurant-id
        " but no restaurant found at location")
    ]
  ]
end

;; Handle courier arrival at customer
to at-destination
  receive-reward

  ;; Remove delivered-to customer
  let temp-job [job-number] of current-job
  if count customers-on patch-here > 0 [
    let temp-customers customers-on patch-here
    ask temp-customers [
      ifelse current-job = temp-job [
        die  ;; Remove completed customer
      ][
        if count customers-on patch-here = 1 [
          print "debug customer not dead"
        ]
      ]
    ]
  ]

  ;; Determine next action based on memory usage
  ifelse use-memory [
    find-best-restaurant     ;; Find optimal restaurant
    move-towards-best-restaurant  ;; Move to best restaurant
  ][
    set status "searching-for-next-job"  ;; Start searching if no memory
    set color green
  ]

  ;; Record completed delivery
  set jobs-performed (insert-item (length jobs-performed) jobs-performed patch-here)
end

;; Evaluate rewards and adjust courier behavior
to check-rewards
  ;; Only check when moving to or waiting at restaurant
  if ((status = "moving-towards-restaurant") or (status = "waiting-for-next-job")) [
    ifelse use-memory [
      find-best-restaurant  ;; Update reward metrics

      ;; High autonomy behavior
      if (autonomy-level = 3) [
        ;; Switch to searching if rewards are low
        if ((current-highest-reward < free-moving-threshold) and (memory-fade > 0)) [
          set status "searching-for-next-job"
          set color green
        ]
        ;; Move to high-reward restaurant
        if (current-highest-reward >= free-moving-threshold) [
          set status "moving-towards-restaurant"
          set color blue
        ]
      ]

      ;; Medium autonomy behavior
      if (autonomy-level = 2) [
        if ((current-highest-reward < free-moving-threshold) and (memory-fade > 0)) [
          set status "searching-for-next-job"
          set color green
        ]
      ]

      ;; Low autonomy behavior
;      if (autonomy-level = 1) [
;        set status "moving-towards-restaurant"
;        set color blue
;        if current-job != nobody [
;          set next-location [origin] of current-job
;        ]
;        if (patch-here = next-location) [
;          set status "waiting-for-next-job"
;          set color orange
;        ]
;      ]

      ;; High cooperation behavior
      if (cooperativeness-level = 3) [
        ;; Future: implement neighbor-based adjustments
      ]
    ] [
      ;; Default to searching without memory
      ;set status "searching-for-next-job"
      ;set color green
    ]
  ]
end

;; Update reward table with latest job
to add-latest-job-to-reward-table [rest-id reward-value]
  let temp-list (table:get reward-list-per-restaurant rest-id)
  ;; Add new reward at start of list
  set temp-list (insert-item 0 temp-list reward-value)
  ;; Remove oldest reward
  set temp-list (remove-item (length temp-list - 1) temp-list)
  ;; Update table
  table:put reward-list-per-restaurant rest-id temp-list
end

;; Identify restaurant with highest expected rewards
to find-best-restaurant
  let max-reward 0
  let best-restaurant 0

  ;; Check each restaurant's reward history
  let i 1
  loop [
    let cur-reward sum table:get reward-list-per-restaurant i

    ;; Update if better than current best
    if cur-reward > max-reward [
      set max-reward cur-reward
      set best-restaurant i
      set current-highest-reward max-reward
      set current-best-restaurant best-restaurant
    ]

    if i = table:length reward-list-per-restaurant [stop]
    set i i + 1
  ]
end

;; Navigate courier to best-performing restaurant
to move-towards-best-restaurant
  let temp-rest-id current-best-restaurant

  ;; Find restaurant location - check if it exists
  let temp-restaurant restaurants with [restaurant-id = temp-rest-id]

  ifelse any? temp-restaurant [
    ;; Restaurant exists, proceed normally
    let temp-patch [patch-here] of one-of temp-restaurant

    ;; Set movement target
    set next-location temp-patch
    face next-location

    ;; Update status
    set status "moving-towards-restaurant"
    set color blue
    set to-origin? false  ;; We're returning to a restaurant, not picking up
  ][
    ;; Restaurant doesn't exist - go to searching mode instead
    print (word "Bike " who " couldn't find restaurant " temp-rest-id)
    set status "searching-for-next-job"
    set color green
  ]
end

;; Process reward for completed delivery
to receive-reward
  ;; Add job reward to total
  set total-reward total-reward + [reward] of current-job

  ;; Update restaurant-specific rewards
  let restaurant-id-temp [restaurant-id] of current-job
  set restaurant-id-temp restaurant-id-temp - 1
  let new-reward item restaurant-id-temp reward-list + [reward] of current-job
  set reward-list replace-item [restaurant-id-temp] of current-job reward-list new-reward

  ;; Update reward history
  add-latest-job-to-reward-table restaurant-id-temp + 1 ([reward] of current-job)
end

;; Apply memory fade to historical rewards
to update-reward-table
  let i 1
  while [i <= restaurant-clusters * restaurants-per-cluster] [
    let temp-list (table:get reward-list-per-restaurant i)

    ;; Update each reward in history
    let j 1
    while [j <= length temp-list] [
      ;; Reduce value by memory-fade percentage
      let new-memory item (length temp-list - j) temp-list * (100 - memory-fade) / 100
      set temp-list replace-item (length temp-list - j) temp-list new-memory
      table:put reward-list-per-restaurant i temp-list
      set j j + 1
    ]
    set i i + 1
  ]
end

;; Update global statistics on courier activities
to count-courier-activities
  ;; Reset counters
  set waiting-couriers 0
  set returning-couriers 0
  set delivering-couriers 0
  set searching-couriers 0
  let grey-couriers 0  ;; Add a counter for couriers in "to-restaurant" state

  ;; Count couriers in each state
  ask couriers [
    if color = green [
      set searching-couriers searching-couriers + 1
    ]
    if color = orange [
      set waiting-couriers waiting-couriers + 1
    ]
    if color = red [
      set delivering-couriers delivering-couriers + 1
    ]
    if color = blue [
      set returning-couriers returning-couriers + 1
    ]
    if color = grey [
      set grey-couriers grey-couriers + 1  ;; Count couriers in "to-restaurant" state
    ]
  ]

  ;; Verify total matches population
  if (waiting-couriers + returning-couriers + delivering-couriers + searching-couriers + grey-couriers != courier-population) [
    print "debug total number of activities couriers unequal to courier-population"
    print (word "Population: " courier-population)
    print (word "Counted: " (waiting-couriers + returning-couriers + delivering-couriers + searching-couriers + grey-couriers))
    print (word "Waiting: " waiting-couriers ", Returning: " returning-couriers ", Delivering: " delivering-couriers ", Searching: " searching-couriers ", To-Restaurant: " grey-couriers)
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
751
552
-1
-1
8.2
1
10
1
1
1
0
0
0
1
-32
32
-32
32
1
1
1
ticks
30.0

BUTTON
10
10
74
43
NIL
Setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
112
11
175
44
NIL
Go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
785
20
957
53
courier-population
courier-population
1
100
3.0
1
1
NIL
HORIZONTAL

SLIDER
781
457
953
490
job-arrival-rate
job-arrival-rate
0
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
783
70
955
103
neighbourhood-size
neighbourhood-size
0
20
10.0
1
1
NIL
HORIZONTAL

PLOT
1139
10
1513
163
on-the-fly jobs vs memory jobs
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Random encounters" 1.0 0 -13345367 true "" "plotxy ticks on-the-fly-jobs"
"Jobs from memory" 1.0 0 -7500403 true "" "plotxy ticks memory-jobs"

SLIDER
780
309
952
342
restaurant-clusters
restaurant-clusters
1
10
3.0
1
1
NIL
HORIZONTAL

SLIDER
777
410
956
443
restaurants-per-cluster
restaurants-per-cluster
1
20
20.0
1
1
NIL
HORIZONTAL

SLIDER
780
357
952
390
cluster-area-size
cluster-area-size
1
20
10.0
1
1
NIL
HORIZONTAL

SLIDER
784
162
956
195
level-of-order
level-of-order
0
100
10.0
1
1
NIL
HORIZONTAL

SWITCH
783
119
912
152
use-memory
use-memory
1
1
-1000

SLIDER
785
206
957
239
memory-fade
memory-fade
0
100
0.0
0.1
1
NIL
HORIZONTAL

PLOT
1146
370
1491
550
Open orders
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count customers"

PLOT
1145
183
1493
352
Current courier activities
NIL
NIL
0.0
10.0
0.0
12.0
true
true
"" ""
PENS
"Out for delivery" 1.0 0 -2674135 true "" "plot delivering-couriers"
"Waiting at rest" 1.0 0 -955883 true "" "plot waiting-couriers"
"Back to rest" 1.0 0 -13345367 true "" "plot returning-couriers"
"Random search" 1.0 0 -10899396 true "" "plot searching-couriers"

SWITCH
785
256
994
289
random-startingpoint-couriers
random-startingpoint-couriers
1
1
-1000

MONITOR
1021
11
1129
56
random vs. memory
on-the-fly-jobs / memory-jobs
1
1
11

SLIDER
12
76
184
109
autonomy-level
autonomy-level
1
3
1.0
1
1
NIL
HORIZONTAL

SLIDER
12
122
184
155
cooperativeness-level
cooperativeness-level
1
3
1.0
1
1
NIL
HORIZONTAL

SWITCH
832
518
982
551
show-cluster-lines
show-cluster-lines
0
1
-1000

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
