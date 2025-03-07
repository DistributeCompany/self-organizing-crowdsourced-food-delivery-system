;; Autonomous Bike Courier Simulation
;; A multi-agent simulation modeling food delivery couriers with varying levels
;; of autonomy and cooperation. The model explores how different decision-making
;; strategies affect overall system efficiency.

;; Future Development Note:
;; In future versions, committed jobs may be canceled/handed-over/stolen
;; while moving towards the restaurant (pick-up location)


;; TODO
;; 2. Use-memory seems to be working, but memory-fade not.
;; 3. customer not dead messages pop up
;; 4. Heterogenous fleet (e.g., some use memory, some don't)
;; 5. Learning with high coop/autonomy. Change agent setting (e.g., use-memory) on the fly, if other agents seem to perform better with that setting
;; 6. Maybe change in update-heatmap to also count the # of agents in the area searching for a job when calculating the competition-factor
;; 7. Check whether in update-temporal-patterns there is a fair balance between latest-demand and history. The prediction-weight should be proper.

;; test with opportunistic-switch on
;; test with force-back-to-rest on
;; check updating of current-heat-score, does not seem to decrease.

;; INSIGHT: with a memory-fade, all jobs will be done onces the demand dies out when ticks -> infinity.
;; coop is about the sharing, autonomy is about the caring (for yourself)
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
  restaurant-instance ;; Instance of originating restaurant
]

;; Courier properties
couriers-own [
  current-job               ;; Currently assigned delivery task
  going-to-rest
  next-location             ;; Where the courier is heading
  current-cluster-location  ;; Current cluster area
  status                    ;; Current state: on-job (red), waiting (orange),
                            ;; searching (green), moving-towards-restaurant (back from delivery: blue, for to-origin?: gray)
  to-origin?                ;; Whether moving to pickup location
  to-destination?           ;; Whether moving to delivery location
  total-reward              ;; Cumulative earnings
  reward-list               ;; History of rewards per restaurant
  reward-list-per-restaurant ;; Table tracking performance at each restaurant
  current-highest-reward    ;; Best available reward after memory fade
  current-best-restaurant   ;; Restaurant with highest expected reward
  jobs-performed      ;; List of completed delivery locations
  last-restaurant-id        ;; The ID of the most recent restaurant the courier visited
  has-done-job?             ;; Whether the courier has performed at least one job
  demand-predictions    ;; Table tracking predicted demand at restaurants
  time-patterns         ;; Table tracking performance by time period
  prediction-history    ;; List of prediction accuracy records
  heat-map              ;; Table storing location scores
  prediction-weight     ;; Balance between prediction vs. actual demand
  waiting-at-restaurant
  job-restaurants     ;; List of restaurants served (instead of just patches)
  job-destinations    ;; List of destinations served (customer locations)
  job-details         ;; List of job details (restaurant, destination, reward, etc.)
  restaurant-occupancy      ;; Table storing known courier counts at restaurants
  occupancy-timestamps      ;; Table storing when occupancy information was last updated
  restaurant-shared-record  ;; Table to track which restaurants this courier has shared information about
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
  current-restaurant      ;; Current restaurant being processed
  waiting-couriers        ;; Count of waiting couriers
  returning-couriers      ;; Count of returning couriers
  delivering-couriers     ;; Count of actively delivering
  searching-couriers      ;; Count of searching couriers

  show-cluster-lines?     ;; Boolean to toggle line visibility

  learning-model        ;; Selected learning model from chooser
  prediction-accuracy   ;; Tracks how accurate predictions are
  time-blocks           ;; For temporal pattern recognition (e.g., morning, afternoon, evening)

  previous-earnings        ;; List of previous courier earnings
  earnings-update-interval ;; How often to update earnings (in ticks)

  ;; Global variables for experiment management
  experiment-running?     ;; Whether an experiment is currently running
  experiment-completed?   ;; Whether the current experiment has completed
  experiment-configs      ;; List of parameter configurations to test
  current-config          ;; The currently active configuration
  current-run             ;; Current run number within configuration
  max-runs                ;; Number of runs per configuration
  run-ticks               ;; How many ticks to run each simulation
  random-seed-base        ;; Base seed for random number generation
  results-data            ;; Table to store results
  data-export-path        ;; File path for exporting results

  ;; KPI tracking
  total-deliveries        ;; Total deliveries completed across all couriers
  avg-delivery-time       ;; Average time from job creation to delivery
  delivery-times          ;; List of all delivery completion times
  courier-utilization     ;; Percentage of couriers actively delivering
  waiting-time-total      ;; Total time couriers spend waiting
  search-time-total       ;; Total time couriers spend searching
  delivery-pay-total      ;; Total courier earnings

  ;; Performance variability metrics
  courier-earnings-sd     ;; Standard deviation of courier earnings
  delivery-time-sd        ;; Standard deviation of delivery times
  courier-deliveries-sd   ;; Standard deviation of deliveries per courier

  ;; variables for analysis
  analysis-data           ;; Table to store analyzed results
  config-summary-stats    ;; Summary statistics by configuration
  autonomy-comparison     ;; Specific comparison of autonomy levels
  performance-variability ;; Measures of performance consistency
]



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                SETUP PROCEDURES                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the simulation
to setup
  clear-all
  reset-ticks

    ;; Set default for job-sharing-algorithm if not already set
  if job-sharing-algorithm = 0 or job-sharing-algorithm = "" [
    set job-sharing-algorithm "Balanced Load"
  ]

   ;; Initialize time blocks for temporal patterns (24-hour clock divided into 4-hour blocks)
  set time-blocks ["0-4" "4-8" "8-12" "12-16" "16-20" "20-24"]

  ;; Initialize learning model from chooser value
  set learning-model learning-model-chooser

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
  set waiting-couriers 0
  set returning-couriers 0
  set delivering-couriers 0
  set searching-couriers 0

  set earnings-update-interval 60
  set previous-earnings []

  ;; Initialize previous earnings after couriers are created
  ask couriers [
    set previous-earnings lput total-reward previous-earnings
  ]
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

  if autonomy-level = 0 [
    ;; Overwrite global variables when autonomy-level = 0 (this ensures that each restaurant has a courier)
    set random-startingpoint-couriers False
    let number-of-restaurants length restaurant-list
    set courier-population number-of-restaurants
  ]

  let i 1

  ;; Create each courier
  while [i <= courier-population] [
    let courier-xcor 0
    let courier-ycor 0
    let cur-status ""
    let cur-color grey
    let temp-restaurant item 0 restaurant-list

    ;; Place courier either randomly or at a restaurant
    ifelse random-startingpoint-couriers [
      ;; Random starting position
      set courier-xcor random-xcor
      set courier-ycor random-ycor
      set cur-status "searching-for-next-job"
      set cur-color green
    ][
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
      set going-to-rest nobody
      set next-location nobody

      ;; Initialize tracking lists
      set jobs-performed []
      set job-restaurants []  ;; List of restaurants served
      set job-destinations [] ;; List of customer locations served
      set job-details []      ;; List of job detail tables

      set has-done-job? false
      ifelse autonomy-level = 0 [
        set last-restaurant-id [restaurant-id] of temp-restaurant
      ]
      [
        set last-restaurant-id -1  ;; Initialize with an invalid ID
      ]



      ;; Initialize reward tracking
      let total-restaurants restaurant-clusters * restaurants-per-cluster
      set reward-list n-values total-restaurants [0]
      create-reward-tables
      set current-highest-reward 0
      set demand-predictions table:make
      set time-patterns table:make
      set prediction-history []  ;; Initialize as an empty list
      set heat-map table:make    ;; Each courier now has its own heat-map
      set prediction-weight start-prediction-weight ;; Initialize prediction weight based on user input
      set waiting-at-restaurant nobody
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
     ; stop
    ]
    set i i + 1
  ]

  ;; After creating couriers and just before the end of the procedure, add:
  ask couriers [

    ;; Initialize demand prediction tables for each restaurant
    let total-restaurants restaurant-clusters * restaurants-per-cluster
    let rest-id 1

    while [rest-id <= total-restaurants] [
      ;; Create a new time pattern table for this restaurant
      let time-pattern-table table:make

      ;; Initialize with zeros for all time blocks
      foreach time-blocks [ time-block ->
        table:put time-pattern-table time-block 0
      ]

      ;; Add to courier's time_patterns
      table:put time-patterns rest-id time-pattern-table

      ;; Set prediction to 0 for this restaurant
      table:put demand-predictions rest-id 0

      ;; Initialize heat map scores for restaurant locations
      let restaurant-agent one-of restaurants with [restaurant-id = rest-id]
      if restaurant-agent != nobody [
        let location-key (word [xcor] of restaurant-agent "," [ycor] of restaurant-agent)
        table:put heat-map location-key 0
      ]

      set restaurant-occupancy table:make  ;; Table to store occupancy information
      set occupancy-timestamps table:make  ;; Table to track information freshness
      set restaurant-shared-record table:make  ;; Table to track which restaurants have been shared

      set rest-id rest-id + 1
    ]
  ]
  debug-courier-knowledge
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
      set label restaurant-id
      set label-color black
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
  ;; Handle time-based patterns
  let current-time-block get-current-time-block

  ask couriers [
     ;; Apply memory fade to all couriers every 60 ticks (= 1 minute)
    if (ticks mod 60 = 0)[
      apply-memory-fade
    ]
    ;; Handle cooperative behavior
    if cooperativeness-level > 0 [
      share-information
    ]

    ;; Execute Demand Prediction if enabled
    if autonomy-level = 3 and learning-model = "Demand Prediction" [
      predict-demand current-time-block
    ]

    ;; Execute Learning if enabled
    if autonomy-level = 3 and learning-model = "Learning and Adaptation" [
      apply-reinforcement-learning
    ]

    ;; Update decisions based on rewards
    check-rewards

    ;; Execute behavior based on current status
    if status = "searching-for-next-job" [
      wiggle
      check-neighbourhood-updated
    ]
    if status = "waiting-for-next-job" [
      check-neighbourhood-updated
    ]

    ;; Apply route evaluation based on learning model
    if status = "moving-towards-restaurant"[
      if autonomy-level = 3 and learning-model = "Demand Prediction" [
        re-evaluate-route-based-on-prediction
      ]
      if autonomy-level = 3 and learning-model = "Learning and Adaptation" [
        re-evaluate-route-based-on-learning
        ]
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
    ]
    ;; Handle job handoffs for high cooperation
    if cooperativeness-level = 3 [
      attempt-job-handoff
    ]
  ]

  ;; Update statistics
  count-courier-activities

  ;; Update prediction accuracy metrics every 50 ticks
  if ticks mod debug-interval = 0 [
    update-prediction-accuracy
    if debug-demand-prediction[
      debug-prediction-performance
    ]
  ]

  ;; Check restaurant colors every 10 ticks
  if ticks mod 10 = 0 [
    update-restaurant-colors
  ]

  ;; Create new jobs based on arrival rate
  if job-arrival-rate > random-float 100 [
    create-job
  ]

  ;; Update earnings data
  update-earnings-data
  if debug-coop and ticks mod debug-interval = 0 [
    debug-courier-knowledge
  ]
  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           AUTONOMY 3 IMPLEMENTATIONS          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Get current time block based on tick number
;; Get current time block based on tick number
to-report get-current-time-block
  ;; Convert ticks to a time-of-day representation (24-hour cycle)
  ;; First convert ticks to minutes, then to hours
  ;; Each tick represents 1 second, 14400 seconds = 4 hours
  let time-of-day floor ((ticks mod 86400) / 3600) ; convert seconds to hours (0-23)

  ;; Return appropriate time block
  if time-of-day >= 0 and time-of-day < 4 [
    report "0-4"
  ]
  if time-of-day >= 4 and time-of-day < 8 [
    report "4-8"
  ]
  if time-of-day >= 8 and time-of-day < 12 [
    report "8-12"
  ]
  if time-of-day >= 12 and time-of-day < 16 [
    report "12-16"
  ]
  if time-of-day >= 16 and time-of-day < 20 [
    report "16-20"
  ]
  report "20-24"  ;; 20-24 time block
end

;; Predict demand at restaurants based on temporal patterns
to predict-demand [current-time-block]
  ;; Skip if courier has no job history
  if not has-done-job? [
    stop
  ]

  ;; Get total number of restaurants
  let total-restaurants restaurant-clusters * restaurants-per-cluster

  ;; For each restaurant, make a prediction
  let i 1
  if debug-demand-prediction and (ticks mod debug-interval = 0)[
    print "=============== UPDATING DEMAND PREDICTION =============="
    print (word "Current Tick: " ticks)
    print(word "   Courier: " who)
  ]

  while [i <= total-restaurants] [
    ;; Check if time_patterns has the restaurant key
    ifelse table:has-key? time-patterns i [
      ;; Get time pattern data for this restaurant
      let rest-time-patterns table:get time-patterns i

      ;; Get current time block's historical performance
      let current-block-value 0
      if table:has-key? rest-time-patterns current-time-block [
        set current-block-value table:get rest-time-patterns current-time-block
      ]

      ;; Check if reward_list_per_restaurant has the restaurant key
      ifelse table:has-key? reward-list-per-restaurant i [
        ;; Get recent actual demand (from reward list)
        let recent-rewards table:get reward-list-per-restaurant i
        let recent-demand 0

        ;; Filter out zero values and calculate average
        let non-zero-rewards filter [ reward-value -> reward-value > 0 ] recent-rewards

        if not empty? non-zero-rewards [
          set recent-demand mean non-zero-rewards  ;; Average of non-zero rewards
        ]

        ;; Calculate predicted demand by combining historical pattern and recent data
        let predicted-demand (current-block-value * prediction-weight) +
                           (recent-demand * (1 - prediction-weight))

        if debug-demand-prediction and (ticks mod debug-interval = 0)[
          print(word "   Restaurant: " i)
          print(word "   Current Time Block: " current-time-block)
          print(word "   Current Time Block Value: " precision current-block-value 2)
          print(word "   Recent Demand: " precision recent-demand 2)
          print(word "   Predicted Demand: " precision predicted-demand 2 " (Based on: "(prediction-weight * 100)"% Time Block / "((1 - prediction-weight) * 100)"% Recent History)")
          print "------------------------------"
        ]
        ;; Update prediction
        table:put demand-predictions i predicted-demand
      ][
        ;; Restaurant not in reward table - initialize with zero
        print (word "Warning: Restaurant " i " not found in reward-list-per-restaurant")
        table:put demand-predictions i 0
      ]
    ][
      ;; Restaurant not in time patterns table - initialize it
      print (word "Warning: Restaurant " i " not found in time-patterns")

      ;; Create a new time pattern table for this restaurant
      let time-pattern-table table:make

      ;; Initialize with zeros for all time blocks
      foreach time-blocks [ time-block ->
        table:put time-pattern-table time-block 0
      ]

      ;; Add to courier's time_patterns
      table:put time-patterns i time-pattern-table

      ;; Set prediction to 0 for this restaurant
      table:put demand-predictions i 0
    ]

    set i i + 1
  ]
  if debug-demand-prediction and (ticks mod debug-interval = 0)[
    print "=============== END DEMAND PREDICTION =============="
  ]
  ;; Update heat map based on predictions
  update-heat-map
end


to update-heat-map
  ;; First, apply decay to existing heat map scores
  ;; This ensures values decrease over time if not refreshed
  ;decay-heat-map-scores

  if debug-memory and (ticks mod debug-interval = 0)[
    print "=============== UPDATING HEATMAP ==============="
    print (word "Current Tick: " ticks)
  ]
  ;; For each restaurant, update its heat map score in this courier's heat map
  let total-restaurants restaurant-clusters * restaurants-per-cluster

  let i 1
  while [i <= total-restaurants] [
    if debug-memory and (ticks mod debug-interval  = 0)[
      print (word "Courier: " who)
      print (word "  Processing Restaurant: " i)
    ]
    ;; Get restaurant location
    let restaurant-agent one-of restaurants with [restaurant-id = i]

    if restaurant-agent != nobody [
      ;; Create location key
      let location-key (word [xcor] of restaurant-agent "," [ycor] of restaurant-agent)

      ;; Calculate heat map score based on multiple factors
      let demand-score 0
      if table:has-key? demand-predictions i [
        set demand-score table:get demand-predictions i
      ]

      ;; Get distance factor - closer is better
      let distance-factor max list 0 (20 - distance restaurant-agent)

      ;; Initialize competition factor and use-competition-factor flag
      let competition-factor 0
      let use-competition-factor? false

      ;; Get waiting couriers at this restaurant only if:
      ;; 1. We're physically close enough to directly observe (within radius neighbourhood-size)
      ;; 2. OR we have fresh shared information through cooperativeness level 2
      ifelse distance restaurant-agent <= neighbourhood-size [
        ;; Direct observation - we can see the restaurant from our current position
        let waiting-count count couriers with [
          status = "waiting-for-next-job" and
          distance restaurant-agent < neighbourhood-size
        ]

        ;; Calculate competition factor based on direct observation
        set competition-factor max list 0 (5 - waiting-count)
        set use-competition-factor? true

        if debug-memory and (ticks mod debug-interval = 0) [
          print (word "     Direct observation - waiting couriers: " waiting-count)
        ]
      ][
        ;; Not close enough for direct observation, check if we have shared information
        if cooperativeness-level >= 2 and table:has-key? restaurant-occupancy i and table:has-key? occupancy-timestamps i [
          ;; We have shared information, check if it's fresh
          let info-age ticks - table:get occupancy-timestamps i

          if info-age <= 300 [  ;; 300 ticks = 5 minutes (fresh information)
            let waiting-count table:get restaurant-occupancy i
            set competition-factor max list 0 (5 - waiting-count)
            set use-competition-factor? true

            if debug-memory and (ticks mod debug-interval = 0) [
              print (word "     Using shared information - waiting couriers: " waiting-count " (data age: " info-age " ticks)")
            ]
          ]

          ;; No need for else clause here - if info is not fresh, we simply don't set use-competition-factor? to true
        ]

        ;; Debug output for no/stale information
        if not use-competition-factor? and debug-memory and (ticks mod debug-interval = 0) [
          print "     No fresh competition information available for this restaurant"
        ]
      ]

      if debug-memory and (ticks mod debug-interval = 0)[
        print (word "     Demand Score: " precision demand-score 2"  (weight: 0.6)")
        print (word "     Distance Factor: " precision distance-factor 2"  (weight: 0.3)")

        if use-competition-factor? [
          print (word "     Competition Factor: " precision competition-factor 2"  (weight: 0.1)")
        ]
      ]

      ;; Calculate overall heat score based on available information
      let heat-score 0

      ifelse use-competition-factor? and cooperativeness-level >= 2 [
        ;; Include competition factor when available
        set heat-score (demand-score * 0.6) + (distance-factor * 0.3) + (competition-factor * 0.1)
      ][
        ;; No competition factor - redistribute weights
        set heat-score (demand-score * 0.7) + (distance-factor * 0.3)
      ]

      if debug-memory and (ticks mod debug-interval = 0)[
        print (word "     Heat Score: " precision heat-score 2)
      ]

      ;; Update heat map - now this is specific to the current courier
      table:put heat-map location-key heat-score
    ]

    set i i + 1
  ]
end

;; Apply decay to all heat map scores to ensure they decrease over time
to decay-heat-map-scores
  ;; Use a moderate decay factor (adjustable)
  let decay-factor 0.95  ;; 5% decay per update

  ;; Convert heat map to list for processing
  let heat-entries table:to-list heat-map

  ;; Apply decay to each entry
  foreach heat-entries [ entry ->
    let loc-key first entry
    let current-value last entry

    ;; Apply decay
    let decayed-value current-value * decay-factor

    ;; Update the heat map with decayed value
    table:put heat-map loc-key decayed-value
  ]
end

;; Re-evaluate route based on predictions
to re-evaluate-route-based-on-prediction
  ;; Skip if user determined that courier first has to go back to restaurant
  if first-go-back-to-rest and status != "waiting-for-next-job" [
    stop
  ]

;; Check for nearby jobs regardless of current job status
  let neighbourhood-jobs jobs with [
    available? and
    distance myself < neighbourhood-size
  ]

  ;; If there are jobs nearby, evaluate them
  if any? neighbourhood-jobs [
     ;; Debug - Found nearby jobs?
    if debug-demand-prediction and (ticks mod 10 = 0)[
      print (word "Current Tick: " ticks)
      print (word "Courier: " who)
      print (word "  Found " count neighbourhood-jobs " jobs in neighbourhood")
    ]

    let best-job max-one-of neighbourhood-jobs [reward]
    let actual-rest-id [restaurant-id] of best-job
    set actual-rest-id actual-rest-id + 1

    ;; Debug - Best job details
    if debug-demand-prediction and (ticks mod 10 = 0) [
      print (word "  Best available job: #" [who] of best-job
        ", Restaurant: " actual-rest-id
        ", Reward: " precision [reward] of best-job 2)
    ]

    ;; Handle different cases based on whether we have a current job
    ifelse current-job = nobody [
      ;; No current job - evaluate based on return destination or opportunistic switch
      ifelse opportunistic-switch [
        ;; Always take best job if opportunistic switching is enabled
        if debug-demand-prediction[
          print (word "Current Tick: " ticks)
          print (word "Courier: " who)
          print (word "  TAKING JOB: Opportunistic switching enabled, taking best job #" [who] of best-job)
        ]

        ;; Take new job
        set current-job best-job
        ask current-job [
          set available? false
        ]

        ;; Set new destination
        set next-location [origin] of current-job
        face next-location
        set to-origin? true
        set to-destination? false
        set going-to-rest [restaurant-instance] of current-job
        set color grey
      ][
        ;; Not opportunistic - compare to expected value of current destination
        ;; Get restaurant we're heading to (if any)
        let current-restaurant-value 0
        let returning-to-restaurant? false

        if status = "moving-towards-restaurant" and not to-origin? [
          ;; We're returning to a restaurant - get its predicted value
          let target-patch next-location
          let target-restaurant one-of restaurants-on target-patch

          if target-restaurant != nobody [
            set returning-to-restaurant? true
            let rest-id [restaurant-id] of target-restaurant

            ;; Get predicted value for this restaurant
            if table:has-key? demand-predictions rest-id [
              set current-restaurant-value table:get demand-predictions rest-id
            ]

            if debug-demand-prediction and (ticks mod 10 = 0) [
              print (word "  Returning to restaurant #" actual-rest-id
                ", Predicted value: " precision current-restaurant-value 2)
            ]
          ]
        ]

        ;; Compare best job to current destination value
        ifelse (not returning-to-restaurant?) or ([reward] of best-job > current-restaurant-value * (1 + switch-threshold / 100)) [
          ;; Take job if it's better than current destination or we're not returning anywhere specific
          if debug-demand-prediction[
            print (word "Current Tick: " ticks)
            print (word "Courier: " who)
            print (word "  TAKING JOB: Job value (" precision [reward] of best-job 2 ") at Restaurant " [restaurant-id] of best-job " is better than going back to Restaurant " [restaurant-id] of going-to-rest  " with value (" precision current-restaurant-value 2 ")")
          ]

          ;; Take new job
          set current-job best-job
          ask current-job [
            set available? false
          ]

          ;; Set new destination
          set next-location [origin] of current-job
          face next-location
          set to-origin? true
          set to-destination? false
          set going-to-rest [restaurant-instance] of current-job

          ;; Color to grey
          set color grey
        ][
          if debug-demand-prediction and (ticks mod 10 = 0) [
            print (word "  NOT TAKING JOB: Current destination value (" precision current-restaurant-value 2
              ") is better than job reward (" precision [reward] of best-job 2 ")")
          ]
        ]
      ]
    ][
      ;; Have current job - original evaluation logic
      let current-reward [reward] of current-job

      ;; Only consider jobs with significantly better reward
      ifelse [reward] of best-job > current-reward * (1 + switch-threshold / 100) [
        ;; Calculate switching cost (progress lost on current delivery)
        let origin-to-dest-distance (distance [origin] of current-job + distance [destination] of current-job)
        let progress-so-far distance [destination] of current-job / origin-to-dest-distance
        let switching-cost current-reward * progress-so-far

        ;; Evaluate whether to switch based on opportunistic-switch or value comparison
        ifelse opportunistic-switch [
          ;; Always switch if opportunistic
          if debug-demand-prediction [
            print (word "Current Tick: " ticks)
            print (word "Courier: " who)
            print (word "  SWITCHING JOBS: Opportunistic switching enabled")
          ]

          ;; Switch jobs
          let old-job-number [who] of current-job
          ask current-job [
            set available? true
          ]

          set current-job best-job
          ask current-job [
            set available? false
          ]

          ;; Set new destination
          set next-location [origin] of current-job
          face next-location
          set to-origin? true
          set to-destination? false
          set going-to-rest [restaurant-instance] of current-job
          set color grey

          if debug-demand-prediction [
            print (word "  Job switch complete: Released #" old-job-number
              ", Now handling #" [who] of current-job)
          ]
        ][
          ;; Standard evaluation - switch if new job is worth more than what we'd lose
          ifelse [reward] of best-job > switching-cost + current-reward [
            ;; Debug - Decision to switch
            if debug-demand-prediction[
              print (word "Current Tick: " ticks)
              print (word "Courier: " who)
              print (word "  Current progress: " precision (progress-so-far * 100) 1 "%"
            ", Switching cost: " precision switching-cost 2)
              print (word "  SWITCHING JOBS: New reward (" precision [reward] of best-job 2
                ") > Current remaining value (" precision (switching-cost + current-reward) 2 ")")
            ]

            ;; Release current job back to available
            let old-job-number [who] of current-job
            ask current-job [
              set available? true
            ]

            ;; Take new job
            set current-job best-job
            ask current-job [
              set available? false
            ]

            ;; Set new destination
            set next-location [origin] of current-job
            face next-location
            set to-origin? true
            set to-destination? false
            set going-to-rest [restaurant-instance] of current-job
            set color grey
            ;; Debug - Confirmation of switch
            if debug-demand-prediction[
              print (word "Courier: " who)
              print (word "  Job switch complete: Released #" old-job-number
                ", Now handling #" [who] of current-job)
            ]
          ][
            ;; Debug - Decision not to switch
            if debug-demand-prediction and (ticks mod 10 = 0) [
              print (word "  NOT SWITCHING: New reward (" precision [reward] of best-job 2
                ") <= Current remaining value (" precision (switching-cost + current-reward) 2 ")")
            ]
          ]
        ]
      ][
        if debug-demand-prediction and (ticks mod 10 = 0)[
          print (word "  NOT SWITCHING: New job reward not significantly better (needs " switch-threshold"% improvement)")
        ]
      ]
    ]
  ]
end

;; Apply reinforcement learning (Learning and Adaptation)
to apply-reinforcement-learning
  ;; This is a placeholder for Autonomy lvl. 3 implementation
  ;; Would contain actual reinforcement learning algorithm
end

;; Apply learned decision (Learning and Adaptation)
to apply-learned-decision
  ;; This is a placeholder for Autonomy lvl. 3 implementation
end

;; Update learned values (Learning and Adaptation)
to update-learned-values [rest-id reward-value]
  ;; This is a placeholder for Autonomy lvl. 3 implementation
end

;; Re-evaluate route based on learning (Learning and Adaptation)
to re-evaluate-route-based-on-learning
  ;; This is a placeholder for Autonomy lvl. 3 implementation
end

;; Re-evaluate current route (placeholder)
to re-evaluate-route
end

;; Attempt to hand off job to another courier (placeholder)
to attempt-job-handoff
end

;; Find the restaurant with highest heat map score
to-report find-best-heat-map-restaurant
  let best-score 0
  let best-id 0

  ;; Loop through all restaurants
  let total-restaurants restaurant-clusters * restaurants-per-cluster
  let i 1

  while [i <= total-restaurants] [
    let restaurant-agent one-of restaurants with [restaurant-id = i]

    if restaurant-agent != nobody [
      ;; Get location key
      let location-key (word [xcor] of restaurant-agent "," [ycor] of restaurant-agent)

      ;; Get heat score from this courier's heat map
      let heat-score 0
      if table:has-key? heat-map location-key [
        set heat-score table:get heat-map location-key
      ]

      ;; Check if this is the best score
      if (heat-score > best-score) and (heat-score > free-moving-threshold) [
        set best-score heat-score
        set best-id i
      ]
    ]

    set i i + 1
  ]

  report best-id
end

;; Debug procedure to evaluate prediction performance
to debug-prediction-performance
  ;; Only run if we have demand prediction enabled
  if autonomy-level != 3 or learning-model != "Demand Prediction" [
    stop
  ]

  ;; Create debug output header
  print "============== DEMAND PREDICTION EVALUATION =============="
  print (word "Current Tick: " ticks)
  print (word "Overall Prediction Accuracy: " precision (prediction-accuracy * 100) 2 "%")

  ;; Sample a few couriers for detailed analysis
  let sample-couriers nobody
  let eligible-couriers couriers with [autonomy-level = 3 and learning-model = "Demand Prediction"]
  if any? eligible-couriers [
    let sample-count min list 3 count eligible-couriers
    set sample-couriers n-of sample-count eligible-couriers
  ]

  print (word "Analyzing " (ifelse-value is-agentset? sample-couriers [count sample-couriers][0]) " sample couriers:")

  ;; For each sample courier, show detailed prediction info
  if is-agentset? sample-couriers and any? sample-couriers [
    ask sample-couriers [
      print (word "  Courier #" who ":")
      print (word "    Total Reward: " precision total-reward 2)
      print (word "    Prediction Weight: " precision prediction-weight 2)

      ;; Show prediction errors if available
      ifelse is-list? prediction-history and not empty? prediction-history [
        print (word "    Recent Prediction Errors: " precision (mean prediction-history) 2)
      ][
        print "    No prediction history yet"
      ]


      ifelse is-list? heat-map or is-string? heat-map or is-number? heat-map [
        print (word "    Error: heat-map is not a table but a ")
      ][
        ifelse table:length heat-map = 0 [
          print "    Heat map is empty"
        ][
          let heat-map-list table:to-list heat-map

          print (word "    Heat map has " length heat-map-list " entries")

          ;; Sort by score and show top 10
          let sorted-locations sort-by [ [a b] -> last a > last b ] heat-map-list
          let count-shown 0

          print "  Top 10 locations:"
          foreach sorted-locations [ location-pair ->
            if count-shown < 10 [
              let loc-key first location-pair
              let score last location-pair

              ;; Parse the location coordinates from the key
              let coord-strings split-string loc-key ","
              let x-coord read-from-string item 0 coord-strings
              let y-coord read-from-string item 1 coord-strings

              ;; Find restaurant at this location
              let restaurant-name "Unknown"
              let restaurant-at-loc one-of restaurants with [xcor = x-coord and ycor = y-coord]

              ;; Get restaurant info if found
              if restaurant-at-loc != nobody [
                set restaurant-name (word "Restaurant #" [restaurant-id] of restaurant-at-loc)
              ]

              ;; Print location with restaurant name
              print (word "    " loc-key " (" restaurant-name ") Heat Score: " precision score 2)
              set count-shown count-shown + 1
            ]
          ]
        ]
      ]

      ;; Show time pattern highlights for one restaurant
      if has-done-job? [
        print "    Time Patterns for Last Restaurant:"
        let rest-id last-restaurant-id
        ifelse table:has-key? time-patterns rest-id [
          let time-table table:get time-patterns rest-id
          foreach time-blocks [ time-block ->
            if table:has-key? time-table time-block [
              let block-score table:get time-table time-block
              print (word "      " time-block ": " precision block-score 2)
            ]
          ]
        ] [
          print "      No time pattern data for this restaurant"
        ]
      ]
    ]
  ]

  ;; Compare prediction vs. actual demand across restaurants
  print "  Restaurant Demand (Predicted vs. Actual):"
  let total-restaurants restaurant-clusters * restaurants-per-cluster
  let sample-restaurants min list 10 total-restaurants
  print (word "  Analyzing " sample-restaurants " sample restaurants:")
  let i 1
  let restaurants-shown 0

  ;; Get a sample courier with demand prediction for checking predictions
  let sample-courier nobody
  if any? couriers with [autonomy-level = 3 and learning-model = "Demand Prediction"] [
    set sample-courier one-of couriers with [autonomy-level = 3 and learning-model = "Demand Prediction"]
  ]

  ifelse sample-courier != nobody [
    while [i <= total-restaurants and restaurants-shown < sample-restaurants] [
      ;; Get courier's prediction for this restaurant
      let predicted 0
      let recent-demand 0
      ask sample-courier [
        if table:has-key? demand-predictions i [
          set predicted table:get demand-predictions i

          ;; Get recent actual demand (from reward list)
          let recent-rewards table:get reward-list-per-restaurant i


          ;; Filter out zero values and calculate average
          let non-zero-rewards filter [ reward-value -> reward-value > 0 ] recent-rewards

          if not empty? non-zero-rewards [
            set recent-demand mean non-zero-rewards  ;; Average of non-zero rewards
          ]
        ]
      ]

      ;; Get actual demand (number of available jobs at restaurant)
      ;let actual-demand count jobs with [available? and restaurant-id = i]

      ;; Evaluate prediction accuracy

      let accuracy-str "Unknown"
      if predicted > 0 or recent-demand > 0 [
        let prediction-diff abs (predicted / recent-demand)
        ifelse prediction-diff < 0.25 or prediction-diff > 1.75 [
          set accuracy-str "Poor"
        ][
          ifelse prediction-diff <= 0.5 or prediction-diff > 1.50 [
            set accuracy-str "Fair"
          ][
            ifelse prediction-diff <= 0.75 or prediction-diff > 1.25 [
              set accuracy-str "Good"
            ][
              set accuracy-str "Excellent"
            ]
          ]
        ]
      ]

      print (word "    Restaurant #" i ": Predicted=" precision predicted 2
             ", Actual=" precision recent-demand 2", Accuracy=" accuracy-str)

      set restaurants-shown restaurants-shown + 1
      set i i + 1
    ]
  ][
    print "    No couriers with demand prediction available for restaurant analysis"
  ]

  ;; Show system-wide impact
  print "  System Impact:"
  print (word "    Heat Map Driven Movements: " count couriers with [color = blue and status = "moving-towards-restaurant"])
  print (word "    Waiting at Predicted Locations: " count couriers with [color = orange and status = "waiting-for-next-job"])
  print (word "    Random Searching: " count couriers with [color = green and status = "searching-for-next-job"])

  print "=============== END PREDICTION EVALUATION ==============="
end

;; Helper function to split a string by delimiter
to-report split-string [string-to-split delimiter]
  let result []
  let current-start 0
  let delimiter-position position delimiter string-to-split

  while [delimiter-position != false] [
    ;; Add the substring to the result
    set result lput (substring string-to-split current-start delimiter-position) result

    ;; Move past this delimiter
    set current-start delimiter-position + 1
    set delimiter-position position delimiter substring string-to-split current-start (length string-to-split)

    ;; Adjust the position to be relative to the original string
    if delimiter-position != false [
      set delimiter-position delimiter-position + current-start
    ]
  ]

  ;; Add the final part
  set result lput (substring string-to-split current-start (length string-to-split)) result

  report result
end

;; Move towards restaurant with high predicted demand
to move-towards-predicted-restaurant [rest-id]
  let target-restaurant one-of restaurants with [restaurant-id = rest-id]

  ifelse target-restaurant != nobody [
    ;; Found restaurant, move towards it
    set next-location [patch-here] of target-restaurant
    face next-location

    ;; Update status to moving
    set status "moving-towards-restaurant"
    set color blue
    set to-origin? false
    set going-to-rest target-restaurant
    set current-job nobody
  ][
    ;; If target restaurant not found, default to searching
    set status "searching-for-next-job"
    set color green
    set waiting-at-restaurant nobody
  ]
end

;; Update predictions with actual outcomes
to update-temporal-patterns [rest-id reward-value]
  ;; Skip if no job history
  if not has-done-job? [
    stop
  ]

  ;; Get current time block
  let current-time-block get-current-time-block

  ;; Get time patterns for this restaurant
  let rest-time-patterns table:get time-patterns rest-id

  ;; Get current value for this time block
  let current-value 0
  if table:has-key? rest-time-patterns current-time-block [
    set current-value table:get rest-time-patterns current-time-block
  ]

  if debug-memory[
  print "=============== UPDATING TEMPORAL PATTERN ==============="
  print (word "Current Tick: " ticks)
  print (word "Courier: " who)
  print (word "Updating temporal pattern for Restaurant: " rest-id)
  print (word "   Current Time Block Value: " precision current-value 2)
  ]
  ;; Update value with exponential moving average

  ;; Note: this value represents the expected reward for a given restaurant at a given time-block (e.g., 12-16).
  ;; This expected reward is specific a a courier. So views on the world might differen between courier agents based on their experience.

  let updated-value (current-value * (1 - learning-rate)) + (reward-value * learning-rate)

  if debug-memory[
  print (word "   Updated Time Block Value: " precision updated-value 2)
  ]
  ;; Store updated value
  table:put rest-time-patterns current-time-block updated-value
  table:put time-patterns rest-id rest-time-patterns

  ;; Also update our overall prediction for this restaurant
  let predicted-demand table:get demand-predictions rest-id
  let prediction-error abs (predicted-demand - reward-value)

  if debug-memory[
  print (word "   Predicted Demand: " predicted-demand)
  print (word "   Actual Reward: " predicted-demand)
  print (word "   Prediction Error: " prediction-error)
  ]
  ;; Record prediction accuracy
  set prediction-history lput prediction-error prediction-history
  if debug-memory[
  print (word "   Prediction Error History: " prediction-history)
  ]
  if length prediction-history > 10 [
    ;; Keep only the last 10 predictions
    set prediction-history but-first prediction-history
  ]

  ;; Adjust prediction weight based on accuracy
  let avg-error mean prediction-history
  if debug-memory[
  print (word "   Avg. Prediction Error: " avg-error)
  ]

  if avg-error > 0 [
    ;; Compare latest error to average error
    let latest-error last prediction-history

    let relative-error latest-error / (avg-error + 0.0001)  ;; Avoid division by zero
    if debug-memory[
    print (word "   Relative Error: " relative-error)
    print (word "   Old Prediction Weight: " precision prediction-weight 2)
    ]
    ;; If latest error is lower than average, reduce prediction weight (trust recent data more)
    ;; If latest error is higher than average, increase prediction weight (trust patterns more)
    ifelse relative-error < 0.8 [
      ;; Recent error is significantly lower - reduce weight to favor recent data
      ;set prediction-weight max list 0.1 (prediction-weight * 0.8)
      if debug-memory[
      print (word "   Weight reduced to favor more accurate recent data")
      ]
    ][
      ifelse relative-error > 1.2 [
        ;; Recent error is significantly higher - increase weight to rely on historical patterns
        ;set prediction-weight min list 0.9 (prediction-weight * 1.2)
        if debug-memory[
        print (word "   Weight increased to favor more reliable historical patterns")
        ]
      ][
        ;; Error is roughly in line with average - minor adjustment
        ;set prediction-weight max list 0.1 min list 0.9 (prediction-weight * (1 + (0.5 - relative-error) / 5))
      ]
    ]
    if debug-memory[
    print (word "   New Prediction Weight: " precision prediction-weight 2)
    print "========================================================="
    ]
  ]
end

;; Update prediction accuracy metrics globally
to update-prediction-accuracy
  let total-accuracy 0
  let courier-count 0

  ask couriers with [autonomy-level = 3 and learning-model = "Demand Prediction"] [
    ;; Make sure prediction-history is a list and not empty before calculating mean
    if is-list? prediction-history and not empty? prediction-history [
      set total-accuracy total-accuracy + (1 - (mean prediction-history / 100))
      set courier-count courier-count + 1
    ]

    ;; Add heat map update here so it's called regularly
    ;update-heat-map
  ]

  if courier-count > 0 [
    set prediction-accuracy total-accuracy / courier-count
  ]
end

;; Main memory fade procedure to be called from the go procedure
to apply-memory-fade
  ;; Only apply memory fade if it's enabled and the rate is greater than 0
  if use-memory and memory-fade > 0 and debug-interval > 0 [
    ;; For debugging - store a courier for monitoring
    let debug-courier-id -1
    ;; Show memory before fade
    if debug-memory and (ticks mod debug-interval = 0) and any? couriers [

      let debug-courier one-of couriers
      set debug-courier-id [who] of debug-courier
      print "=============== APPLYING MEMORY FADE ==============="
      print (word "BEFORE FADE (Tick " ticks ", Strategy: " fade-strategy ", Rate: " memory-fade "%):")
      debug-print-memory debug-courier
    ]

    ;; Apply the selected fade strategy to all couriers
    ask couriers [
      (ifelse
        fade-strategy = "None" [
          ;; No memory fade - do nothing
        ]
        fade-strategy = "Linear" [
          ;; Notes on memory-fade parameter
          ;; Range: 0.5% - 10%
          ;; Typical values: 1-5%
          ;; Explanation:
          ;; Since linear fade applies the same reduction to all memories,
          ;; even small values can have a significant cumulative effect over time.
          ;; Values above 10% may cause memories to fade too quickly.

          apply-linear-fade
        ]
        fade-strategy = "Exponential" [
          ;; Notes on memory-fade parameter
          ;; Range: 1% - 15%
          ;; Typical values: 3-8%
          ;; Explanation:
          ;; Since the this algorithm applies stronger decay to older memories while preserving newer ones, you can use slightly higher values than with linear fade.
          ;; The exponential effect makes older memories fade quickly even with moderate parameter values.

          apply-exponential-fade
        ]
        fade-strategy = "Recency-weighted" [
          ;; Notes on memory-fade parameter
          ;; Range: 2% - 20%
          ;; Typical values: 5-12%
          ;; Explanation:
          ;; This algorithm is designed to strongly preserve recent memories while allowing older ones to fade more rapidly.
          ;; It can handle higher fade rates without losing important recent information.

          apply-recency-weighted-fade
        ]
      )
    ]

      ;; After applying fade, update the current-highest-reward and current-best-restaurant
      find-best-restaurant

    ;; Show memory after fade for the same courier
    if debug-memory and (ticks mod debug-interval = 0) and any? couriers and debug-courier-id >= 0 [
      let same-courier one-of couriers with [who = debug-courier-id]
      if same-courier != nobody [
        print (word "AFTER FADE (Tick " ticks ", Strategy: " fade-strategy ", Rate: " memory-fade "%):")
        debug-print-memory same-courier
        print "-------------------------------------------------------------"
      ]
    ]
  ]
end

;; Linear fade - applies an equal percentage reduction to all memories
to apply-linear-fade
  let fade-rate memory-fade / 100  ;; Convert percentage to decimal

  ;; Apply to each restaurant's memory
  let i 1
  while [i <= table:length reward-list-per-restaurant] [
    let rewards table:get reward-list-per-restaurant i
    let new-rewards map [ reward-value -> reward-value * (1 - fade-rate) ] rewards
    table:put reward-list-per-restaurant i new-rewards
    set i i + 1
  ]
end

;; Exponential fade - applies stronger fade to older memories
to apply-exponential-fade
  let base-rate memory-fade / 100  ;; Convert percentage to decimal

  ;; Apply to each restaurant's memory
  let i 1
  while [i <= table:length reward-list-per-restaurant] [
    let rewards table:get reward-list-per-restaurant i
    let new-rewards []

    ;; Calculate exponential decay for each position
    let j 0
    foreach rewards [ reward-value ->
      ;; Newer entries (index 0) have minimal decay, older entries decay more
      let position-factor j / (length rewards - 1)  ;; 0 for newest, 1 for oldest
      let decay-factor (1 - base-rate) ^ (1 + position-factor * 2)  ;; Exponential decay
      set new-rewards lput (reward-value * decay-factor) new-rewards
      set j j + 1
    ]

    table:put reward-list-per-restaurant i new-rewards
    set i i + 1
  ]
end

;; Recency-weighted fade - more sophisticated model that weights recent experiences more heavily
to apply-recency-weighted-fade
  let fade-rate memory-fade / 100  ;; Convert percentage to decimal

  ;; Apply to each restaurant's memory
  let i 1
  while [i <= table:length reward-list-per-restaurant] [
    let rewards table:get reward-list-per-restaurant i
    let new-rewards []

    ;; Calculate recency weights
    let total-weight 0
    let weights []

    ;; Generate weights - higher for recent rewards
    let j 0
    repeat length rewards [
      ;; Calculate weight: newest (j=0) gets highest weight
      let recency-weight exp(- j * 0.5)  ;; Exponential recency weight
      set weights lput recency-weight weights
      set total-weight total-weight + recency-weight
      set j j + 1
    ]

    ;; Normalize weights to sum to 1
    set weights map [ w -> w / total-weight ] weights

    ;; Apply fade with recency weighting
    set j 0
    foreach rewards [ reward-value ->
      let weight item j weights
      let decay-factor 1 - (fade-rate * (1 - weight) * 2)  ;; More weight = less decay
      if decay-factor < 0 [ set decay-factor 0 ]  ;; Ensure non-negative
      set new-rewards lput (reward-value * decay-factor) new-rewards
      set j j + 1
    ]

    table:put reward-list-per-restaurant i new-rewards
    set i i + 1
  ]
end

;; Debugging procedure - print memory details for a courier
to debug-print-memory [courier-agent]
  ;; Print courier ID
  print (word "  Courier ID: " [who] of courier-agent)

  ;; Print total reward
  print (word "  Total reward: " precision [total-reward] of courier-agent 2)

  ;; Print memory for first few restaurants (to avoid excessive output)
  print "  Restaurant memories (showing only first x restaurants):"
  let count-shown 0
  let i 1

  while [i <= table:length [reward-list-per-restaurant] of courier-agent and count-shown < 8] [
    let restaurant-memory table:get [reward-list-per-restaurant] of courier-agent i

    ;; Check if restaurant has any memory entries
    ifelse length restaurant-memory > 0 [
      ;; Format the memory values for display
      let formatted-memory ""
      foreach restaurant-memory [ reward-value ->
        set formatted-memory (word formatted-memory " " precision reward-value 2)
      ]

      ;; Print the memory for this restaurant
      print (word "    Restaurant " i ": [" formatted-memory " ]")
      set count-shown count-shown + 1
    ][
      ;; Skip empty memory
      print (word "    Restaurant " i ": [empty]")
    ]

    set i i + 1

  ]
    ;; Print summary of current best restaurant and highest reward
    print (word "  Current best restaurant: " [current-best-restaurant] of courier-agent)
    print (word "  Current highest reward: " precision [current-highest-reward] of courier-agent 2)
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
    set restaurant-instance temp-rest
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

  ;; Update restaurant color to indicate pending job
  ask temp-rest [
    set color orange
  ]
end

;; Check for available jobs in courier's neighborhood
to check-neighbourhood
    ;; For autonomy level 0, use the restricted version
  if autonomy-level = 0 [
    check-neighbourhood-level-zero
    stop
  ]

  ;; Check logic for higher autonomy levels
  if autonomy-level > 0 and count jobs in-radius neighbourhood-size > 0 [
    let test count jobs
   ; print (word "Courier:" who "Jobs in radius: " test)
    let temp-job one-of jobs in-radius neighbourhood-size

    ;; Try to take available job
    if [available?] of temp-job [
      set current-job temp-job
      ask current-job [
        set available? false
      ]

      ;; If this is the courier's first job, record the restaurant
      if not has-done-job? [
        set has-done-job? true
        set last-restaurant-id [restaurant-id] of current-job
      ]

      ;; Set movement target
      set next-location [origin] of current-job
      face next-location

      ;; Update job statistics
      if status = "waiting-for-next-job" [
        set memory-jobs memory-jobs + 1
      ]
      if color = green [
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
        set going-to-rest nobody

        ;; Check if this was the last job at the restaurant
        let rest-id [restaurant-id] of current-job
        let remaining-jobs count jobs with [available? and restaurant-id = rest-id]

        if remaining-jobs = 0 [
          ;; Update restaurant color if this was the last available job
          ask restaurants with [restaurant-id = rest-id] [
            set color white
          ]
        ]
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

;; Check jobs at the first restaurant only
to check-neighbourhood-level-zero
  ;; Only look for jobs at the exact same restaurant
  let target-restaurant-id last-restaurant-id  ;; Use the courier's latest restaurant
  let jobs-at-restaurant jobs with [available? and restaurant-id = target-restaurant-id]

  if any? jobs-at-restaurant [
    let temp-job one-of jobs-at-restaurant

    ;; Take the job
    set current-job temp-job
    ask current-job [
      set available? false
    ]

    ;; Set movement target
    set next-location [origin] of current-job
    face next-location

    ;; Update job statistics
    set memory-jobs memory-jobs + 1

    ;; Update status
    set status "on-job"
    set color red
    set to-origin? false
    set to-destination? true
    set next-location [destination] of current-job
    face next-location
    set going-to-rest [restaurant-instance] of current-job

    ;; Check if this was the last job at the restaurant
    let remaining-jobs count jobs with [available? and restaurant-id = target-restaurant-id]

    if remaining-jobs = 0 [
      ;; Update restaurant color if this was the last available job
      ask restaurants with [restaurant-id = target-restaurant-id] [
        set color white
      ]
    ]
  ]
end

;; Check if courier has reached destination
to check-on-location

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
        ;; Returned to restaurant after delivery
        set status "waiting-for-next-job"
        set color orange
      ]
    ]

    if (status = "on-job") and (to-destination?) and (distance next-location < 0.5) [
      ;; Arrived at customer
      ;print (word "Courier:" who " arrived at customer " next-location)
      at-destination
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
    ;; Check if there are any remaining available jobs at this restaurant
    let remaining-jobs count jobs with [available? and restaurant-id = job-restaurant-id]

    ;; Only change color to white if no more jobs are available at this restaurant
    if remaining-jobs = 0 [
      ask target-restaurant [
        set color white
      ]
    ]
  ][
    ;; Alternative: Look for any restaurant on this patch
    let local-restaurants restaurants-on patch-here
    ifelse any? local-restaurants [
      ;; Check for any remaining jobs at this location
      let restaurant-patch patch-here
      let remaining-jobs count jobs with [available? and origin = restaurant-patch]

      if remaining-jobs = 0 [
        ask local-restaurants [
          set color white
        ]
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
  record-delivery [tick-number] of current-job

  ;; Store job information before removing it
  let temp-job-number [job-number] of current-job
  let job-restaurant-id [restaurant-id] of current-job
  let job-restaurant-instance [restaurant-instance] of current-job
  let job-reward [reward] of current-job

  ;; Always update the last restaurant ID
  set last-restaurant-id job-restaurant-id
  set has-done-job? true

  ;; Store job information as a list containing origin restaurant ID,
  ;; destination patch, and reward - we use restaurant ID since
  ;; restaurant-instance is a turtle and may be gone later
  set jobs-performed lput (list job-restaurant-id patch-here job-reward) jobs-performed

  set going-to-rest job-restaurant-instance

  ;; Remove the job instance
  ask current-job [
    die  ;; Remove completed job
  ]

  set current-job nobody  ;; Clear the current-job reference

  ;; Remove delivered-to customer
  if count customers-on patch-here > 0 [
    let temp-customers customers-on patch-here
    ask temp-customers [
      if current-job = temp-job-number [
        die  ;; Remove completed customer
      ]
    ]
  ]

  ;; Determine next action based on autonomy level
  ifelse autonomy-level < 3 and has-done-job? [
    ;; Autonomy level 0-1-2: Always return to first/last restaurant
    move-towards-specific-restaurant last-restaurant-id
  ][
    ;; Higher autonomy levels: Use memory or search
    ifelse use-memory [
      find-best-restaurant     ;; Find optimal restaurant
      move-towards-best-restaurant  ;; Move to best restaurant
    ][
      set status "searching-for-next-job"  ;; Start searching if no memory
      set color green
      set waiting-at-restaurant nobody
    ]
  ]
end

to move-towards-specific-restaurant [rest-id]
  ;; Find restaurant with the given ID
  let target-restaurant one-of restaurants with [restaurant-id = rest-id]

  ifelse target-restaurant != nobody [
    ;; Restaurant exists, proceed to it
    let target-patch [patch-here] of target-restaurant

    ;; Set movement target
    set next-location target-patch
    face next-location

    ;; Update status
    set status "moving-towards-restaurant"
    set color blue  ;; Use blue for returning to restaurant
    set to-origin? false  ;; Not picking up, just returning
    set going-to-rest target-restaurant
    set current-job nobody
  ][
    ;; If target restaurant doesn't exist, fallback to searching
    print (word "Bike " who " couldn't find target restaurant " rest-id)
    set status "searching-for-next-job"
    set color green
    set waiting-at-restaurant nobody
  ]
end

;; Evaluate rewards and adjust courier behavior
to check-rewards
;; For autonomy level 0, just check if we're at the destination
  if autonomy-level = 0 [
    if status = "waiting-for-next-job" [
      ;; Check for jobs at this specific restaurant
      check-neighbourhood-level-zero
    ]
    ;; No other behavior changes for autonomy level 0
    stop
  ]

  ;; Autonomy 3 with Demand Prediction model
  if autonomy-level = 3 and learning-model = "Demand Prediction" and has-done-job? [
    ;; Use prediction-based decision making
    if status = "waiting-for-next-job" or status = "searching-for-next-job" [
      ;; First ensure our heat map is up-to-date with latest faded values
      ;update-heat-map

      ;; Then decide whether to stay, search locally, or relocate based on heat map
      let current-location-key (word xcor "," ycor)
      let current-heat-score 0

      ;; Get current location heat score if it exists
      if table:has-key? heat-map current-location-key [
        set current-heat-score table:get heat-map current-location-key
      ]

      ;; Find the restaurant with the highest heat score
      let best-restaurant-id find-best-heat-map-restaurant

      ;; If we're at a restaurant, check if any jobs are available first
      if status = "waiting-for-next-job" [
        check-neighbourhood-updated
      ]

      ;; Check if courier is already at the best restaurant
      let at-best-restaurant? false
      let actual-res-id best-restaurant-id + 1

      if best-restaurant-id > 0 [
        let best-restaurant one-of restaurants with [restaurant-id = best-restaurant-id]
        if best-restaurant != nobody [
          if (xcor = [xcor] of best-restaurant and ycor = [ycor] of best-restaurant) [
            set at-best-restaurant? true
            if debug-demand-prediction and (ticks mod 10 = 0) [
             ; print (word "Courier #" who " is already at the best restaurant #" actual-res-id)
            ]
          ]
        ]
      ]

      ;; If we didn't find a job and current location score is low, consider moving
      if (status = "waiting-for-next-job")[
        if debug-demand-prediction and (ticks mod debug-interval = 0) [
           print "---------------------------------------------"
            print (word " Courier: " who)
            print (word "   Status: " status)
           print (word "   Current Heat Score: " precision current-heat-score 2)
        ]
        ifelse current-heat-score < free-moving-threshold [
          if debug-demand-prediction[
            print (word " Courier: " who)
            print (word "   Status: " status)
            print (word "   LEAVE RESTAURANT: Current Heat Score (" precision current-heat-score 2
              ") < Threshold (" precision free-moving-threshold 2 ")")
            ifelse best-restaurant-id > 0 [
              print (word "   Best option: Restaurant # " best-restaurant-id)
            ][
              print (word "   No known restaurant with Heat Score above Threshold!")
              print ("   Let's go exploring!")
            ]
          ]

          ;; Current location not promising, move to better restaurant
          ifelse best-restaurant-id > 0 and not at-best-restaurant? [
            if debug-demand-prediction[
              print (word "   Moving To Restaurant # " best-restaurant-id)
            ]
            move-towards-predicted-restaurant best-restaurant-id
          ][
            ;; Skip movement if already at best restaurant
           ; ifelse at-best-restaurant? [
           ;   if debug-demand-prediction and (ticks mod 10 = 0) [
           ;     print "   Already at best restaurant, staying put"
           ;   ]
           ; ][
            if debug-demand-prediction and  at-best-restaurant?[
              print "   Already at best restaurant, let's explore!"
            ]
              set status "searching-for-next-job" ;; No good predictions, switch to searching
              set color green
              set waiting-at-restaurant nobody
           ; ]
          ]
        ][
          ;; Current location is still promising, stay or search locally
          ifelse status = "waiting-for-next-job" [
            ;; Already waiting, continue to wait - will wait until a job in neighbourhood arrives

            ;; Update temporal patterns to include that 0 demand has been found at the restaurant
            if (ticks mod debug-interval = 0)[
              let rest-id 0  ;; Default value
              carefully [
                ifelse is-agent? going-to-rest [
                  set rest-id [restaurant-id] of going-to-rest
                ][
                  ifelse is-agentset? going-to-rest and any? going-to-rest [
                    set rest-id [restaurant-id] of one-of going-to-rest
                  ][
                    print "Warning: going-to-rest is not a valid agent or agentset"
                  ]
                ]
              ][
                print error-message
              ]
              let reward-value 0
              if debug-memory[
              print "----------------------------------------------------------"
              print "Updating temporal patterns because waiting at restaurant!"
              print "----------------------------------------------------------"
              ]
            update-temporal-patterns rest-id reward-value
            ]
          ][
            ;; If searching, check if we should stay put
            let nearby-restaurant one-of restaurants in-radius 2
            if nearby-restaurant != nobody [
              ;; Stop searching and wait at this restaurant
              set status "waiting-for-next-job"
              set color orange
              setxy [xcor] of nearby-restaurant [ycor] of nearby-restaurant
              set waiting-at-restaurant nearby-restaurant
            ]
          ]
        ]
      ]
    ]
    stop
  ]

  ;; Autonomy 3 with Learning and Adaptation model
  if autonomy-level = 3 and learning-model = "Learning and Adaptation" and has-done-job? [
    ;; Apply reinforcement learning behavior
    if status = "waiting-for-next-job" or status = "searching-for-next-job" [
      ;; Implement reinforcement learning decision here
      apply-learned-decision
    ]
    stop
  ]

  ;; Check logic for other autonomy levels
  if ((status = "moving-towards-restaurant") or (status = "waiting-for-next-job")) [
    ;; Medium autonomy behavior
    if ((autonomy-level = 2) and (status = "waiting-for-next-job"))[

      if (status = "waiting-for-next-job") and ((current-highest-reward < free-moving-threshold) and (memory-fade > 0) and (total-reward > 0)) [
        ;; Modified behavior for cooperativeness level 2
        ;; Instead of random searching, go to least crowded restaurant
        ifelse cooperativeness-level >= 2 [
          if ticks mod debug-interval = strategic-repositioning-interval[
            move-to-least-crowded-restaurant
          ]
        ][
          ;; Original behavior for cooperativeness level < 2
          set status "searching-for-next-job"
          set color green
          set waiting-at-restaurant nobody
        ]
      ]
    ]
  ]
end

;; Check and update restaurant colors
to update-restaurant-colors
  ;; This can be called periodically to ensure restaurant colors are correct
  ask restaurants [
    let rest-id restaurant-id
    let has-jobs any? jobs with [available? and restaurant-id = rest-id]

    ifelse has-jobs [
      set color orange
    ][
      set color white
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

;; Identify nearby restaurant with highest expected rewards
to find-best-local-restaurant
  let max-reward 0
  let best-restaurant 0
  let nearby-restaurants []

  ;; First identify all restaurants within neighbourhood-size
  let i 1
  let total-restaurants table:length reward-list-per-restaurant

  while [i <= total-restaurants] [
    ;; Find the restaurant agent
    let restaurant-agent one-of restaurants with [restaurant-id = i]

    ;; Check if restaurant is within neighbourhood-size
    if restaurant-agent != nobody and distance restaurant-agent <= neighbourhood-size [
      ;; Add to our list of nearby restaurants
      set nearby-restaurants lput i nearby-restaurants
    ]

    set i i + 1
  ]

  ;; If no nearby restaurants found, use the original global search as fallback
  ifelse empty? nearby-restaurants [
    ;; Call the original procedure if no nearby restaurants
    find-best-restaurant
  ][
    ;; Only evaluate restaurants in the nearby list
    foreach nearby-restaurants [ rest-id ->
      let cur-reward 0

      ;; Calculate average of non-zero rewards for this restaurant
      let rewards table:get reward-list-per-restaurant rest-id

      ;; Filter out zero values
      let non-zero-rewards filter [ reward-value -> reward-value > 0 ] rewards

      ;; Calculate average if there are any non-zero values
      ifelse not empty? non-zero-rewards [
        set cur-reward mean non-zero-rewards
      ][
        set cur-reward 0  ;; If all values are zero, set reward to 0
      ]

      ;; Debug output if needed
      if debug-memory and (ticks mod debug-interval = 0) [
        print (word "Courier " who " evaluating nearby restaurant " rest-id
              ", distance: " precision (distance one-of restaurants with [restaurant-id = rest-id]) 2
              ", reward: " precision cur-reward 2)
      ]

      ;; Update if better than current best
      if cur-reward > max-reward [
        set max-reward cur-reward
        set best-restaurant rest-id
      ]
    ]

    ;; Update courier's best restaurant and reward values
    set current-highest-reward max-reward
    set current-best-restaurant best-restaurant

    ;; Debug output if needed
    if debug-memory and (ticks mod debug-interval = 0) [
      print (word "Courier " who " chose local restaurant " best-restaurant
            " with expected reward " precision max-reward 2)
    ]
  ]
end

;; Identify restaurant with highest expected rewards
to find-best-restaurant
  let max-reward 0
  let best-restaurant 0

  ;; Check each restaurant's reward history
  let i 1
  loop [
    let cur-reward 0

    ;; Sum all rewards in the list for this restaurant
    let rewards table:get reward-list-per-restaurant i
    foreach rewards [ reward-value ->
      set cur-reward cur-reward + reward-value
    ]

    ;; Update if better than current best
    if cur-reward > max-reward [
      set max-reward cur-reward
      set best-restaurant i
    ]

    if i = table:length reward-list-per-restaurant [
      ;; Update courier's best restaurant and reward values
      set current-highest-reward max-reward
      set current-best-restaurant best-restaurant
      stop
    ]
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
    set going-to-rest temp-restaurant
    set current-job nobody
  ][
    ;; Restaurant doesn't exist - go to searching mode instead
    print (word "Courier " who " couldn't find restaurant " temp-rest-id)
    set status "searching-for-next-job"
    set color green
    set waiting-at-restaurant nobody
  ]
end

;; Process reward for completed delivery
to receive-reward
  ;; Add job reward to total
  set total-reward total-reward + [reward] of current-job

  ;; Get restaurant ID
  let restaurant-id-temp [restaurant-id] of current-job

  ;; Update restaurant-specific rewards
  set restaurant-id-temp restaurant-id-temp - 1
  let new-reward item restaurant-id-temp reward-list + [reward] of current-job
  set reward-list replace-item [restaurant-id-temp] of current-job reward-list new-reward

  ;; Update reward history
  add-latest-job-to-reward-table restaurant-id-temp + 1 ([reward] of current-job)

  ;; For Autonomy 3 with Demand Prediction, update temporal patterns
  if autonomy-level = 3 and learning-model = "Demand Prediction" [
    update-temporal-patterns restaurant-id-temp + 1 ([reward] of current-job)
  ]

  ;; For Autonomy 3 with Learning and Adaptation, update learned values
  if autonomy-level = 3 and learning-model = "Learning and Adaptation" [
    update-learned-values restaurant-id-temp + 1 ([reward] of current-job)
  ]
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


;; Reporter to calculate the average prediction weight of all couriers
to-report avg-prediction-weight
  ;; First check if there are any couriers using prediction
  let prediction-couriers couriers with [
    autonomy-level = 3 and
    learning-model = "Demand Prediction"
  ]

  ;; If no couriers, return 0
  if not any? prediction-couriers [
    report 0
  ]

  ;; Calculate the average prediction weight
  let total-weight sum [prediction-weight] of prediction-couriers
  let courier-count count prediction-couriers

  report total-weight / courier-count
end

;; Reporter to get a list of all courier prediction weights
to-report all-prediction-weights
  ;; First check if there are any couriers using prediction
  let prediction-couriers couriers with [
    autonomy-level = 3 and
    learning-model = "Demand Prediction"
  ]

  ;; If no couriers, return empty list
  if not any? prediction-couriers [
    report "No prediction couriers"
  ]

  ;; Create a string representation of all weights
  let weights-list []
  ask prediction-couriers [
    set weights-list lput precision prediction-weight 2 weights-list
  ]

  ;; Sort the list for better readability
  set weights-list sort weights-list

  ;; Convert to string with average at the beginning
  let avg precision (sum weights-list / length weights-list) 2
  report (word "Avg: " avg ", Values: " weights-list)
end

to-report earnings-per-interval
  let current-earnings []
  let earnings-rates []

  ;; Collect current earnings
  ask couriers [
    set current-earnings lput total-reward current-earnings
  ]

  ;; Only calculate if we have previous earnings and ticks > 0
  ifelse not empty? previous-earnings and ticks > 0 [
    ;; Calculate rate for each courier
    let i 0
    while [i < length current-earnings] [
      let current-value item i current-earnings
      let previous-value item i previous-earnings
      let rate current-value - previous-value
      set earnings-rates lput rate earnings-rates
      set i i + 1
    ]

    ;; Update previous earnings for next calculation
    set previous-earnings current-earnings

    ;; Return earnings rates
    report earnings-rates
  ][
    ;; If first run or no previous data, update previous earnings
    ;; but report zeros to avoid division errors
    set previous-earnings current-earnings
    report n-values length current-earnings [0]
  ]
end

to update-earnings-data
  ;; Only update at the specified interval
  if ticks mod earnings-update-interval = 0 [
    ;; This updates previous-earnings and returns the rates
    let rates earnings-per-interval
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;              ANALYSIS PROCEDURES              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Load and analyze experimental results
to analyze-experiment-results [file-path]
  set analysis-data table:make
  set config-summary-stats table:make

  ;; Load data from CSV
  carefully [
    file-open file-path

    ;; Skip header line
    let header file-read-line

    ;; Read each data line
    while [not file-at-end?] [
      let line file-read-line
      let fields csv-to-list line

      ;; Get configuration key and data
      let config-key item 0 fields
      let run-key item 1 fields

      ;; Parse numeric data
      let data []
      let i 2
      while [i < length fields] [
        carefully [
          set data lput read-from-string item i fields data
        ][
          set data lput 0 data  ;; Default to 0 if parsing fails
        ]
        set i i + 1
      ]

      ;; Store in analysis data
      ifelse table:has-key? analysis-data config-key [
        let config-data table:get analysis-data config-key
        table:put config-data run-key data
        table:put analysis-data config-key config-data
      ][
        let new-config-data table:make
        table:put new-config-data run-key data
        table:put analysis-data config-key new-config-data
      ]
    ]

    file-close

    ;; Calculate summary statistics
    calculate-summary-statistics

    ;; Compare autonomy levels
    compare-autonomy-levels

    ;; Analyze performance variability
    analyze-performance-variability

    ;; Display summary
    print "Experiment results loaded and analyzed successfully."
    print (word "Number of configurations: " table:length analysis-data)
    print "Summary statistics calculated."

  ][
    print (word "Error loading results file: " error-message)
  ]
end

;; Parse CSV line into list
to-report csv-to-list [csv-line]
  let result []
  let current-field ""
  let in-quotes? false
  let chars []

  ;; Convert string to character list
  let i 0
  while [i < length csv-line] [
    set chars lput item i csv-line chars
    set i i + 1
  ]

  ;; Parse fields
  foreach chars [ c ->
    if c = "\"" [
      set in-quotes? not in-quotes?
    ]

    ifelse c = "," and not in-quotes? [
      ;; End of field
      set result lput current-field result
      set current-field ""
    ][
      if c != "\"" [ ;; Skip quote characters
        set current-field (word current-field c)
      ]
    ]
  ]

  ;; Add the last field
  set result lput current-field result

  report result
end

;; Calculate summary statistics for each configuration
to calculate-summary-statistics
  foreach table:keys analysis-data [ config-key ->
    let config-data table:get analysis-data config-key
    let summary-stats table:make

    ;; For each metric (position in data array)
    let metric-count 11 ;; Number of metrics
    let metric-idx 0

    while [metric-idx < metric-count] [
      ;; Collect all values for this metric across runs
      let metric-values []

      foreach table:keys config-data [ run-key ->
        let run-data table:get config-data run-key
        set metric-values lput item metric-idx run-data metric-values
      ]

      ;; Calculate mean, min, max, and SD
      let metric-mean mean metric-values
      let metric-min min metric-values
      let metric-max max metric-values
      let metric-sd standard-deviation-report metric-values

      ;; Store summary statistics
      table:put summary-stats (word "metric_" metric-idx) (list metric-mean metric-min metric-max metric-sd)

      set metric-idx metric-idx + 1
    ]

    ;; Store configuration summary
    table:put config-summary-stats config-key summary-stats
  ]
end

;; Compare autonomy levels specifically
to compare-autonomy-levels
  ;; Find configurations that only vary by autonomy level
  let autonomy-configs []

  foreach table:keys analysis-data [ config-key ->
    ;; Check if this configuration is an autonomy test
    if position "autonomy-level" config-key != false [
      set autonomy-configs lput config-key autonomy-configs
    ]
  ]

  ;; Group by autonomy level
  let autonomy-0-data []
  let autonomy-1-data []
  let autonomy-2-data []
  let autonomy-3-data []

  foreach autonomy-configs [ config-key ->
    ifelse position "autonomy-level=0" config-key != false [
      set autonomy-0-data lput config-key autonomy-0-data
    ][
      ifelse position "autonomy-level=1" config-key != false [
        set autonomy-1-data lput config-key autonomy-1-data
      ][
        ifelse position "autonomy-level=2" config-key != false [
          set autonomy-2-data lput config-key autonomy-2-data
        ][
          if position "autonomy-level=3" config-key != false [
            set autonomy-3-data lput config-key autonomy-3-data
          ]
        ]
      ]
    ]
  ]

  ;; Calculate averages across each autonomy level for key metrics
  set autonomy-comparison table:make

  ;; Key metrics to analyze: Deliveries (0), Avg Time (1), Earnings (3), Utilization (7)
  let metrics-to-compare [0 1 3 7]
  let metric-names ["TotalDeliveries" "AvgDeliveryTime" "AvgEarnings" "CourierUtilization"]

  let autonomy-levels [0 1 2 3]
  let autonomy-data-lists (list autonomy-0-data autonomy-1-data autonomy-2-data autonomy-3-data)

  let metric-idx 0
  foreach metrics-to-compare [ metric ->
    let metric-name item metric-idx metric-names
    let metric-results []

    let level-idx 0
    foreach autonomy-levels [ level ->
      let level-configs item level-idx autonomy-data-lists
      let level-values []

      ;; Get all values for this level and metric
      foreach level-configs [ config-key ->
        let summary-stats table:get config-summary-stats config-key
        let metric-stats table:get summary-stats (word "metric_" metric)
        let metric-mean first metric-stats
        set level-values lput metric-mean level-values
      ]

      ;; Calculate average for this autonomy level
      let level-avg 0
      ifelse not empty? level-values [
        set level-avg mean level-values
      ][
        set level-avg -1  ;; Indicates no data
      ]

      set metric-results lput level-avg metric-results
      set level-idx level-idx + 1
    ]

    ;; Store results for this metric
    table:put autonomy-comparison metric-name metric-results

    set metric-idx metric-idx + 1
  ]

  ;; Print comparison
  print "Autonomy Level Comparison:"
  foreach metric-names [ metric-name ->
    let values table:get autonomy-comparison metric-name
    print (word metric-name ": ")
    let level-idx 0
    foreach autonomy-levels [ level ->
      let value item level-idx values
      ifelse value >= 0 [
        print (word "  Level " level ": " precision value 2)
      ][
        print (word "  Level " level ": No data")
      ]
      set level-idx level-idx + 1
    ]
  ]
end


;; Analyze performance variability
to analyze-performance-variability
  set performance-variability table:make

  foreach table:keys config-summary-stats [ config-key ->
    let summary-stats table:get config-summary-stats config-key

    ;; Get variability metrics
    let earnings-var item 3 table:get summary-stats "metric_4"  ;; EarningsSD
    let delivery-time-var item 3 table:get summary-stats "metric_2"  ;; DeliveryTimeSD
    let deliveries-var item 3 table:get summary-stats "metric_6"  ;; DeliveriesPerCourierSD

    ;; Store variability metrics
    table:put performance-variability config-key (list earnings-var delivery-time-var deliveries-var)
  ]

  ;; Print variability analysis
  print "Performance Variability Analysis:"
  foreach table:keys performance-variability [ config-key ->
    let variability-metrics table:get performance-variability config-key
    print (word config-key ":")
    print (word "  Earnings Variability: " precision (item 0 variability-metrics) 2)
    print (word "  Delivery Time Variability: " precision (item 1 variability-metrics) 2)
    print (word "  Deliveries Variability: " precision (item 2 variability-metrics) 2)
  ]
end

;; Setup comparative plots for visualization
to setup-comparative-plots
  clear-all-plots

  ;; Plot autonomy level comparison
  if table:length autonomy-comparison > 0 [
    set-current-plot "Autonomy Level Comparison"

    ;; Plot deliveries by autonomy level
    set-current-plot-pen "Deliveries"
    let delivery-values table:get autonomy-comparison "TotalDeliveries"
    let i 0
    foreach delivery-values [ val ->
      plotxy i val
      set i i + 1
    ]

    ;; Plot earnings by autonomy level
    set-current-plot-pen "Earnings"
    set i 0
    let earnings-values table:get autonomy-comparison "AvgEarnings"
    foreach earnings-values [ val ->
      plotxy i val
      set i i + 1
    ]

    ;; Plot utilization by autonomy level
    set-current-plot-pen "Utilization"
    set i 0
    let util-values table:get autonomy-comparison "CourierUtilization"
    foreach util-values [ val ->
      plotxy i (val * 100)  ;; Convert to percentage
      set i i + 1
    ]
  ]

  ;; Plot variability measures
  if table:length performance-variability > 0 [
    set-current-plot "Performance Variability"

    ;; Find autonomy configs
    let autonomy-configs []
    let i 0
    repeat 4 [
      let autonomy-level-val i
      let matching-configs filter [config -> position (word "autonomy-level=" autonomy-level-val) config != false] table:keys performance-variability

      ifelse not empty? matching-configs [
        let config-key first matching-configs
        let variability-metrics table:get performance-variability config-key

        ;; Plot earnings variability
        set-current-plot-pen "Earnings Var"
        plotxy i item 0 variability-metrics

        ;; Plot delivery time variability
        set-current-plot-pen "Time Var"
        plotxy i item 1 variability-metrics

        ;; Plot deliveries variability
        set-current-plot-pen "Deliveries Var"
        plotxy i item 2 variability-metrics
      ][
        ;; No data for this autonomy level
      ]

      set i i + 1
    ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          COOPERATIVENESS PROCEDURES           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; This will be called from check-neighbourhood when cooperativeness-level = 1
to check-neighbourhood-with-sharing
  ;; Only apply sharing for autonomy levels 1 and higher
  if autonomy-level <= 0 [
    check-neighbourhood  ;; Fall back to standard behavior
    stop
  ]

  ;; Find all available jobs in neighborhood
  let nearby-jobs jobs with [
    available? and
    distance myself < neighbourhood-size
  ]

  if any? nearby-jobs [
    ;; Select a job to potentially take
    let temp-job one-of nearby-jobs

    ;; Find all waiting couriers in the neighborhood of this job
    let eligible-couriers couriers with [
      (status = "waiting-for-next-job"or status = "searching-for-next-job") and
      distance temp-job < neighbourhood-size
    ]

    ;; Debug output when debug-coop is on
    if debug-coop and ticks mod debug-interval = 0 [
      print "=============== COOPERATIVE SHARING DEBUG ==============="
      print (word "Courier: " who)
      print (word "Current tick: " ticks)
      print (word "Job: #" [who] of temp-job ", Reward: " precision [reward] of temp-job 2)
      print (word "Restaurant ID: " [restaurant-id] of temp-job)
      print (word "Eligible couriers: " count eligible-couriers)

      ;; List all eligible couriers with their stats
      print "Courier details:"
      ask eligible-couriers [
        print (word "  Courier #" who
               ", Jobs: " length jobs-performed
               ", Total reward: " precision total-reward 2)
      ]

      print (word "Selected algorithm: " job-sharing-algorithm)
    ]

    ;; Apply sharing algorithm based on user choice
    ifelse job-sharing-algorithm = "Balanced Load" [
      balanced-load-sharing eligible-couriers temp-job
    ][
      if job-sharing-algorithm = "Proportional Fairness" [
        proportional-fairness-sharing eligible-couriers temp-job
      ]
    ]
  ]
end

;; Algorithm 1: Balanced Load Sharing
;; Couriers with fewer completed jobs get priority
;; In case of a tie, the first courier gets the job
to balanced-load-sharing [eligible-couriers temp-job]
  if any? eligible-couriers [
    ;; Get the minimum number of jobs among all eligible couriers
    let min-jobs-count min [length jobs-performed] of eligible-couriers

    ;; Check if all couriers have the same number of jobs (a tie)
    let all-same-jobs? true
    let job-counts []

    ask eligible-couriers [
      set job-counts lput (length jobs-performed) job-counts
      if length jobs-performed != min-jobs-count [
        set all-same-jobs? false
      ]
    ]

    ;; Find courier with fewest completed jobs (we want to give them priority)
    ;; In case of a tie, select the courier with the lowest who number (first courier)
    let min-jobs-courier nobody

    ifelse all-same-jobs? [
      ;; All couriers have the same number of jobs - select the one with lowest who number
      set min-jobs-courier min-one-of eligible-couriers [who]

      if debug-coop and ticks mod debug-interval = 0 [
        print "  TIE DETECTED: All couriers have the same number of jobs"
        print (word "  Selecting courier with lowest ID: #" [who] of min-jobs-courier)
      ]
    ][
      ;; Normal case - select courier with fewest jobs
      set min-jobs-courier min-one-of eligible-couriers [length jobs-performed]
    ]

    ;; Debug output
    if debug-coop and ticks mod debug-interval = 0 [
      print (word "BALANCED LOAD ALGORITHM:")
      print (word "  Courier with fewest jobs: #" [who] of min-jobs-courier
             " (" [length jobs-performed] of min-jobs-courier " jobs)")
      print (word "  Current courier: #" who " (" length jobs-performed " jobs)")
      print (word "  Decision: " ifelse-value (min-jobs-courier = self) ["Taking job"] ["Deferring to courier with fewer jobs"])
    ]

    ;; If I am the selected courier, take the job
    ifelse min-jobs-courier = self [
      ;; Take the job
      set current-job temp-job
      ask current-job [
        set available? false
      ]

      ;; Update status and statistics
      set next-location [origin] of current-job
      face next-location

      ;; Update job statistics
      if status = "waiting-for-next-job" [
        set memory-jobs memory-jobs + 1
      ]

      ;; Set movement target
      ifelse (distance next-location < 0.5) [
        ;; Already at restaurant - go directly to on-job
        set status "on-job"
        set color red
        set to-origin? false
        set to-destination? true
        set next-location [destination] of current-job
        face next-location
        set going-to-rest nobody

        if debug-coop  and ticks mod debug-interval = 0[
          print "  Already at restaurant, moving directly to customer"
        ]
      ][
        ;; Need to go to restaurant first
        set status "moving-towards-restaurant"
        set color grey
        set to-origin? true
        set to-destination? false

        if debug-coop and ticks mod debug-interval = 0 [
          print "  Moving to restaurant for pickup"
        ]
      ]
    ][
      ;; If I'm not the selected courier, I defer to them
      ;; Do nothing - the selected courier will take it
    ]
  ]
end


;; Algorithm 2: Proportional Fairness Sharing
;; Probability of accepting a job is inversely proportional to total reward
to proportional-fairness-sharing [eligible-couriers temp-job]
  if any? eligible-couriers [
    ;; Get job reward
    let job-reward [reward] of temp-job

    ;; Calculate all eligible couriers' total rewards
    let all-rewards []
    let courier-ids []

    ask eligible-couriers [
      set all-rewards lput total-reward all-rewards
      set courier-ids lput who courier-ids
    ]

    ;; To avoid division by zero for couriers with no rewards yet
    let min-reward 0.1
    let adjusted-rewards map [r -> max list r min-reward] all-rewards

    ;; Calculate inverse proportional weights
    ;; Smaller total_reward = higher chance to get job
    let sum-inverse-rewards sum (map [r -> 1 / r] adjusted-rewards)
    let weights []
    let my-weight 0
    let my-index 0
    let current-index 0

    ;; Find my index in the courier list
    set my-index position who courier-ids
    if my-index = false [
      set my-index -1  ;; Not found in the list
    ]

    ;; Calculate weights for all couriers
    let i 0
    while [i < length adjusted-rewards] [
      let courier-reward item i adjusted-rewards
      let courier-weight (1 / courier-reward) / sum-inverse-rewards
      set weights lput courier-weight weights

      if i = my-index [
        set my-weight courier-weight
      ]

      set i i + 1
    ]

    ;; Debug output for weights
    if debug-coop [
      print "PROPORTIONAL FAIRNESS ALGORITHM:"
      print "  Courier weights (lower rewards = higher chance):"

      let index 0
      while [index < length weights] [
        let courier-id item index courier-ids
        let weight item index weights
        let actual-reward item index all-rewards
        print (word "    Courier #" courier-id ": Weight "
               precision (weight * 100) 2 "%, Reward "
               precision actual-reward 2)
        set index index + 1
      ]
    ]

    ;; Use stochastic assignment based on weights
    let random-value random-float 1.0
    let cumulative-weight 0
    let selected-index -1
    let j 0

    while [j < length weights and selected-index = -1] [
      set cumulative-weight cumulative-weight + item j weights
      if random-value <= cumulative-weight [
        set selected-index j
      ]
      set j j + 1
    ]

    ;; Debug the selection process
    if debug-coop [
      print (word "  Random value: " precision random-value 4)
      print (word "  Selected index: " selected-index)
      print (word "  My index: " my-index)
      print (word "  Decision: " ifelse-value (selected-index = my-index) ["Taking job"] ["Job assigned to another courier"])
    ]

    ;; If I am the selected courier, take the job
    if selected-index = my-index [
      ;; Take the job
      set current-job temp-job
      ask current-job [
        set available? false
      ]

      ;; Update status and statistics
      set next-location [origin] of current-job
      face next-location

      ;; Update job statistics
      if status = "waiting-for-next-job" [
        set memory-jobs memory-jobs + 1
      ]

      ;; Set movement target
      ifelse (distance next-location < 0.5) [
        ;; Already at restaurant - go directly to on-job
        set status "on-job"
        set color red
        set to-origin? false
        set to-destination? true
        set next-location [destination] of current-job
        face next-location
        set going-to-rest nobody

        if debug-coop [
          print "  Already at restaurant, moving directly to customer"
        ]
      ][
        ;; Need to go to restaurant first
        set status "moving-towards-restaurant"
        set color grey
        set to-origin? true
        set to-destination? false

        if debug-coop [
          print "  Moving to restaurant for pickup"
        ]
      ]
    ]
  ]
end

;; Share local job information with nearby couriers
;; Called from share-information procedure when cooperativeness-level = 1
to share-local-job-info
  ;; Only applicable for cooperativeness-level 1
  if cooperativeness-level != 1 [
    stop
  ]

  ;; Find all jobs in neighborhood
  let nearby-jobs jobs with [
    available? and
    distance myself < neighbourhood-size
  ]

  ;; Find all nearby couriers to share with
  let nearby-couriers other couriers with [
    distance myself < neighbourhood-size
  ]

  ;; For cooperativeness-level 1, just make sure other couriers
  ;; are aware of these jobs (no action needed in this model since
  ;; all agents can already see all jobs in their neighborhood)
end

;; Modified check-neighbourhood to handle cooperative behavior
to check-neighbourhood-updated
  ;; For autonomy level 0, use the restricted version
  if autonomy-level = 0 [
    check-neighbourhood-level-zero
    stop
  ]

  ;; Apply cooperative behavior for level 1 and higher
  if cooperativeness-level > 0 [
    check-neighbourhood-with-sharing
    stop
  ]

  ;; Original check-neighbourhood logic for other cases
  if autonomy-level > 0 and count jobs in-radius neighbourhood-size > 0 [
    let test count jobs
    let temp-job one-of jobs in-radius neighbourhood-size

    ;; Try to take available job
    if [available?] of temp-job [
      set current-job temp-job
      ask current-job [
        set available? false
      ]

      ;; If this is the courier's first job, record the restaurant
      if not has-done-job? [
        set has-done-job? true
        set last-restaurant-id [restaurant-id] of current-job
      ]

      ;; Set movement target
      set next-location [origin] of current-job
      face next-location

      ;; Update job statistics
      if status = "waiting-for-next-job" [
        set memory-jobs memory-jobs + 1
      ]
      if color = green [
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
        set going-to-rest nobody

        ;; Check if this was the last job at the restaurant
        let rest-id [restaurant-id] of current-job
        let remaining-jobs count jobs with [available? and restaurant-id = rest-id]

        if remaining-jobs = 0 [
          ;; Update restaurant color if this was the last available job
          ask restaurants with [restaurant-id = rest-id] [
            set color white
          ]
        ]
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

;; Updated share-information procedure to include level 1 behavior
to share-information
  ;; Different sharing strategies based on cooperativeness level
  if cooperativeness-level = 1 [
    share-local-job-info
  ]

  ;; New implementation for cooperativeness level 2
  if cooperativeness-level = 2 [
    share-restaurant-occupancy
  ]

  ;; Level 3 would be implemented in future work
  if cooperativeness-level = 3 [
    ;; Existing placeholder for level 3
    ;; (Future: implement job handoff)
  ]
end

;; New procedure for couriers to share restaurant occupancy information
to share-restaurant-occupancy
  ;; Only execute for cooperativeness level 2
  if cooperativeness-level != 2 [
    stop
  ]
  if debug-coop and ticks mod debug-interval = 0[
  debug-sharing-event
  ]
  ;; Initialize restaurant-shared-record if it doesn't exist
 ; if not is-list? restaurant-shared-record and not is-string? restaurant-shared-record [
  ;  set restaurant-shared-record table:make
; ]

  ;; First, update our own knowledge about restaurants in our vicinity
  let visible-restaurants restaurants in-radius neighbourhood-size

  ;; Observe and record information about all restaurants we can see
  if any? visible-restaurants [
    ask visible-restaurants [
      let this-restaurant self
      let rest-id restaurant-id

      ;; Count how many couriers are at this restaurant
      let couriers-at-restaurant count couriers with [
        status = "waiting-for-next-job" and
        distance this-restaurant < 2
      ]

      ;; Have the courier remember what it directly observed
      ask myself [
        ;; Direct observations use current tick as the timestamp
        if debug-coop and ticks mod debug-interval = 0 [
        debug-direct-observation this-restaurant couriers-at-restaurant
        ]
        remember-restaurant-occupancy this-restaurant couriers-at-restaurant ticks "direct observation"
      ]
    ]
  ]

  ;; Now share information with nearby couriers
  let nearby-couriers other couriers in-radius neighbourhood-size

  if any? nearby-couriers [
    ;; Share ALL our restaurant knowledge with nearby couriers
    if table:length restaurant-occupancy > 0 [
      ;; Create a list of restaurant information to share
      let sharing-data []

      ;; Prepare data about each restaurant we know about
      foreach table:keys restaurant-occupancy [ rest-id-str ->
        ;; Ensure rest-id is a number
        let rest-id rest-id-str
        if is-string? rest-id [
          carefully [
            set rest-id read-from-string rest-id
          ][
            ;; Skip if we can't parse the ID
            stop
          ]
        ]

        ;; Get our information about this restaurant
        let couriers-count table:get restaurant-occupancy rest-id

        ;; Important: Use the original observation timestamp, not current tick
        let observation-time table:get occupancy-timestamps rest-id

        ;; Find the restaurant agent
        let restaurant-agent one-of restaurants with [restaurant-id = rest-id]

        if restaurant-agent != nobody [
          ;; Add to our sharing data
          set sharing-data lput (list restaurant-agent couriers-count observation-time) sharing-data
        ]
      ]

      ;; Share all our knowledge with each nearby courier
      if not empty? sharing-data [
        ask nearby-couriers [
          foreach sharing-data [ data-item ->
            let restaurant-agent item 0 data-item
            let couriers-count item 1 data-item
            let observation-time item 2 data-item

            ;; Receive this information
            remember-restaurant-occupancy restaurant-agent couriers-count observation-time "shared information"
          ]
        ]

        ;; Record that we ourselves shared this information
        foreach sharing-data [ data-item ->
          let restaurant-agent item 0 data-item
          let rest-id [restaurant-id] of restaurant-agent

          ;; Make sure we have this in our own records as a restaurant we've shared info about
          table:put restaurant-shared-record rest-id true
        ]

        ;; Debug output
        if debug-coop and ticks mod debug-interval = 0 [
          print "=============== COOPERATIVE SHARING (LEVEL 2) ==============="
          print (word "Courier: " who)
          print (word "Current tick: " ticks)
          print (word "Shared information about " length sharing-data " restaurants with " count nearby-couriers " nearby couriers")
          print "Shared restaurant information:"
          foreach sharing-data [ data-item ->
            let restaurant-agent item 0 data-item
            let couriers-count item 1 data-item
            let observation-time item 2 data-item
            let age ticks - observation-time
            print (word "  Restaurant #" [restaurant-id] of restaurant-agent ": "
                  couriers-count " couriers (data age: " age " ticks)")
          ]
        ]
      ]
    ]
  ]
end


;; Procedure for a courier to remember occupancy information about a restaurant
to remember-restaurant-occupancy [shared-restaurant couriers-count observation-time source-type]
  ;; Initialize tables if they don't exist
 ; if not is-list? restaurant-occupancy and not is-string? restaurant-occupancy [
 ;   print "creating occupancy table..."
 ;   set restaurant-occupancy table:make
 ; ]

  ;if not is-list? occupancy-timestamps and not is-string? occupancy-timestamps [
  ;  print "creating teimstampy table..."
  ;  set occupancy-timestamps table:make
  ;]

  ;if not is-list? restaurant-shared-record and not is-string? restaurant-shared-record [
  ;  set restaurant-shared-record table:make
  ;]

  ;; Get restaurant ID
  let rest-id [restaurant-id] of shared-restaurant

  ;; Only update if this information is fresher than what we already have
  let should-update? true

  if table:has-key? occupancy-timestamps rest-id [
    let existing-timestamp table:get occupancy-timestamps rest-id

    ;; Only update if the new observation is more recent
    set should-update? observation-time > existing-timestamp

    ;; Skip updating if this is the sharing courier receiving info about their own shared data
    if source-type = "shared information" and observation-time = existing-timestamp [
      set should-update? false

      if debug-coop  and ticks mod debug-interval = 0[
        print (word "Courier " who " ignored redundant information about Restaurant #" rest-id)
      ]
    ]
  ]

  ;; Update our knowledge if the information is fresher
  if should-update? [
    table:put restaurant-occupancy rest-id couriers-count
    table:put occupancy-timestamps rest-id observation-time

    ;; Debug output if enabled
    if debug-coop  and ticks mod debug-interval = 0[
      let data-age ticks - observation-time
      print (word "Courier " who " updated restaurant information:")
      print (word "  Restaurant #" rest-id " has " couriers-count " couriers")
      print (word "  Information source: " source-type)
      print (word "  Information age: " data-age " ticks")
    ]
  ]
end

to move-to-least-crowded-restaurant
  ;; Only proceed if we have restaurant occupancy data
  if not is-table? restaurant-occupancy or table:length restaurant-occupancy = 0 [
    ;; No data available, fall back to original behavior
    set status "searching-for-next-job"
    set color green
    set waiting-at-restaurant nobody

  ;  if debug-coop and ticks mod debug-interval = 0 [
      print (word "Courier " who " has no restaurant occupancy data, using random search")
  ;  ]
    stop
  ]

  ;; Find the restaurant with the minimum number of couriers
  let least-crowded-id -1
  let min-couriers 999

  foreach table:keys restaurant-occupancy [ rest-id-str ->
    ;; Convert string key to number if needed
    let rest-id rest-id-str
    if is-string? rest-id [
      carefully [
        set rest-id read-from-string rest-id
      ][
        ;; Skip this entry if we can't parse the rest-id
        stop
      ]
    ]

    let couriers-count table:get restaurant-occupancy rest-id

    ;; Check if information is recent enough (within last 5 minutes)
    let is-fresh? false
    if table:has-key? occupancy-timestamps rest-id [
      let info-age ticks - table:get occupancy-timestamps rest-id
      set is-fresh? info-age <= 300  ;; 300 ticks = 5 minutes
    ]

    ;; Only consider fresh information
    if is-fresh? and couriers-count < min-couriers [
      set min-couriers couriers-count
      set least-crowded-id rest-id
    ]
  ]

  ;; If we found a valid restaurant, move towards it
  ifelse least-crowded-id > 0 [
    let target-restaurant one-of restaurants with [restaurant-id = least-crowded-id]

    if target-restaurant != nobody [
      ;; Restaurant exists, proceed to it
      set next-location [patch-here] of target-restaurant
      face next-location

      ;; Update status
      set status "moving-towards-restaurant"
      set color blue  ;; Blue for strategic movement
      set to-origin? false
      set going-to-rest target-restaurant
      set current-job nobody

    ;  if debug-coop [
        print (word "Courier " who " strategically moving to restaurant #" least-crowded-id)
        print (word "  This restaurant has " min-couriers " couriers (lowest known)")
     ; ]
    ]
  ][
    ;; No valid target found, fall back to random search
    set status "searching-for-next-job"
    set color green
    set waiting-at-restaurant nobody

  ;  if debug-coop [
      print (word "Courier " who " found no suitable restaurant, using random search")
  ;  ]
  ]
end

;; Procedure to debug courier knowledge tables
to debug-courier-knowledge
  ;; Print header
  print "============= DEBUGGING COURIER KNOWLEDGE ============="
  print (word "Current tick: " ticks)

  ;; Create a list of all couriers for easier examination
  let all-couriers sort couriers

  ;; Print information for each courier
  foreach all-couriers [ c ->
    ask c [
      print (word "\n=> COURIER " who " <============")
      print (word "Status: " status)

      ;; Check for correct initialization
      print "\nTABLE INITIALIZATION CHECK:"
      print (word "restaurant-occupancy is a table: " is-table? restaurant-occupancy)
      print (word "occupancy-timestamps is a table: " is-table? occupancy-timestamps)
      print (word "restaurant-shared-record is a table: " is-table? restaurant-shared-record)

      ;; Print restaurant occupancy table
      print "\nRESTAURANT OCCUPANCY TABLE:"
      ifelse is-table? restaurant-occupancy [
        let entries table:to-list restaurant-occupancy
        ifelse not empty? entries [
          foreach entries [ entry ->
            let rest-id first entry
            let counts last entry
            print (word "  Restaurant #" rest-id ": " counts " couriers")
          ]
        ][
          print "  <empty table>"
        ]
      ][
        print "  <not a table>"
      ]

      ;; Print timestamps table
      print "\nOCCUPANCY TIMESTAMPS TABLE:"
      ifelse is-table? occupancy-timestamps [
        let entries table:to-list occupancy-timestamps
        ifelse not empty? entries [
          foreach entries [ entry ->
            let rest-id first entry
            let timestamp last entry
            print (word "  Restaurant #" rest-id ": timestamp " timestamp " (age: " (ticks - timestamp) " ticks)")
          ]
        ][
          print "  <empty table>"
        ]
      ] [
        print "  <not a table>"
      ]

      ;; Print shared record table
      print "\nRESTAURANT SHARED RECORD TABLE:"
      ifelse is-table? restaurant-shared-record [
        let entries table:to-list restaurant-shared-record
        ifelse not empty? entries [
          foreach entries [ entry ->
            let rest-id first entry
            print (word "  Restaurant #" rest-id ": shared information")
          ]
        ][
          print "  <empty table>"
        ]
      ][
        print "  <not a table>"
      ]

      ;; Check for inconsistencies
      if is-table? restaurant-occupancy and is-table? occupancy-timestamps [
        print "\nCONSISTENCY CHECK:"
        let occupancy-keys table:keys restaurant-occupancy
        let timestamp-keys table:keys occupancy-timestamps

        ;; Check for restaurants in occupancy but not in timestamps
        foreach occupancy-keys [ k ->
          if not table:has-key? occupancy-timestamps k [
            print (word "  WARNING: Restaurant #" k " exists in occupancy table but not in timestamps table")
          ]
        ]

        ;; Check for restaurants in timestamps but not in occupancy
        foreach timestamp-keys [ k ->
          if not table:has-key? restaurant-occupancy k [
            print (word "  WARNING: Restaurant #" k " exists in timestamps table but not in occupancy table")
          ]
        ]
      ]

      ;; Add summary about nearby restaurants
      print "\nCURRENT ENVIRONMENT:"
      let visible-restaurants restaurants in-radius neighbourhood-size
      print (word "  Restaurants within neighborhood: " count visible-restaurants)
      if any? visible-restaurants [
        print "  Nearby restaurants:"
        ask visible-restaurants [
          let waiting-count count couriers with [
            status = "waiting-for-next-job" and
            distance myself < 2
          ]
          print (word "    Restaurant #" restaurant-id ": " waiting-count " waiting couriers")
        ]
      ]

      ;; Add information about nearby couriers
      let nearby-couriers other couriers in-radius neighbourhood-size
      print (word "  Couriers within neighborhood: " count nearby-couriers)
      if any? nearby-couriers [
        print "  Nearby couriers: "
        foreach sort nearby-couriers [ nc ->
          print (word "    Courier #" [who] of nc)
        ]
      ]
    ]
  ]

  print "\n============= END DEBUGGING ============="
end

;; Helper reporter to check if a variable is a table
to-report is-table? [var]
  report is-list? var = false and is-string? var = false and is-number? var = false and var != 0 and var != false
end

;; Procedure to trace a specific direct observation event - call before remember-restaurant-occupancy
to debug-direct-observation [restaurant-agent couriers-at-restaurant]
  print "============= DIRECT OBSERVATION TRACE ============="
  print (word "Courier: " who)
  print (word "Current tick: " ticks)
  print (word "Observing Restaurant #" [restaurant-id] of restaurant-agent)
  print (word "Observed courier count: " couriers-at-restaurant)

  ;; Print current state before update
  print "\nCURRENT STATE BEFORE UPDATE:"
  ifelse is-table? restaurant-occupancy and table:has-key? restaurant-occupancy [restaurant-id] of restaurant-agent [
    print (word "  Current occupancy record: " table:get restaurant-occupancy [restaurant-id] of restaurant-agent)
  ][
    print "  No existing occupancy record"
  ]

  ifelse is-table? occupancy-timestamps and table:has-key? occupancy-timestamps [restaurant-id] of restaurant-agent [
    print (word "  Current timestamp record: " table:get occupancy-timestamps [restaurant-id] of restaurant-agent)
  ][
    print "  No existing timestamp record"
  ]

  print "============= END TRACE ============="
end

;; Procedure to trace a sharing event - call at the beginning of share-restaurant-occupancy
to debug-sharing-event
  print "============= SHARING EVENT TRACE ============="
  print (word "Courier: " who)
  print (word "Current tick: " ticks)

  ;; Print current state of tables
  print "\nCURRENT KNOWLEDGE BEFORE SHARING:"
  ifelse is-table? restaurant-occupancy [
    let entries table:to-list restaurant-occupancy
    ifelse not empty? entries [
      foreach entries [ entry ->
        let rest-id first entry
        let counts last entry
        let timestamp "unknown"
        if is-table? occupancy-timestamps and table:has-key? occupancy-timestamps rest-id [
          set timestamp table:get occupancy-timestamps rest-id
        ]
        print (word "  Restaurant #" rest-id ": " counts " couriers (timestamp: " timestamp ")")
      ]
    ][
      print "  <no restaurant knowledge to share>"
    ]
  ][
    print "  <restaurant-occupancy is not a table>"
  ]

  ;; Print info about nearby couriers
  let nearby-couriers other couriers in-radius neighbourhood-size
  print (word "\nFound " count nearby-couriers " couriers nearby:")
  if any? nearby-couriers [
    foreach sort nearby-couriers [ nc ->
      print (word "  Courier #" [who] of nc)
    ]
  ]

  print "============= END TRACE ============="
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;              EXPERIMENT PROCEDURES            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Define experiment configurations
to setup-experiments
  ;; Initialize experiment-running? if it hasn't been initialized yet
  if not is-boolean? experiment-running? [
    set experiment-running? false
  ]

  if experiment-running? [
    user-message "An experiment is already running. Please wait for it to complete or stop it manually."
    stop
  ]

  ;; Initialize experiment variables
  set experiment-running? true
  set experiment-completed? false
  set current-run 1
  set experiment-configs []
  set results-data table:make

  ;; Get experiment parameters from interface
  set max-runs experiment-runs-per-config
  set run-ticks experiment-ticks-per-run
  set random-seed-base experiment-base-seed
  set data-export-path (word "courier_experiment_results_" date-and-time-report ".csv")

  ;; Build configuration list based on user selections
  build-configuration-list

  ;; If no configurations, stop
  if empty? experiment-configs [
    user-message "No experiment configurations defined."
    set experiment-running? false
    stop
  ]

  ;; Set first configuration and initialize
  set current-config first experiment-configs
  setup-configuration current-config
  reset-kpis

  ;; Create results data structure
  ;initialize-results-table

  ;; Display experiment info
  print (word "Starting experiment with " length experiment-configs " configurations, "
    max-runs " runs per configuration, for " run-ticks " ticks each.")
  print (word "Base random seed: " random-seed-base)
  print "First configuration:"
  print current-config
end

;; Build list of configurations to test
to build-configuration-list
  ;; If testing autonomy levels
  if vary-autonomy? [
    let autonomy-values [0 1 2 3]

    foreach autonomy-values [ a-val ->
      ;; Create a list containing a single parameter pair
      let config (list (list "autonomy-level" a-val))

      ;; If also varying cooperativeness
      ifelse vary-cooperativeness? [
        let coop-values [1 2 3]

        foreach coop-values [ c-val ->
          ;; Create a list containing two parameter pairs
          let combined-config (list (list "autonomy-level" a-val) (list "cooperativeness-level" c-val))
          set experiment-configs lput combined-config experiment-configs
        ]
      ][
        ;; Just autonomy variation
        set experiment-configs lput config experiment-configs
      ]
    ]
  ]
  ;; If testing memory effects
  if vary-memory? [
    ;; Combinations of use-memory and memory-fade
    let memory-settings [[true 0.5] [true 5] [true 10] [false 0]]

    foreach memory-settings [ mem-setting ->
      ;; Create a list of parameter pairs
      let config (list
        (list "use-memory" first mem-setting)
        (list "memory-fade" last mem-setting)
      )
      set experiment-configs lput config experiment-configs
    ]
  ]

  ;; If testing prediction weight for Autonomy Level 3
  if vary-prediction-weight? [
    let weight-values [0.1 0.3 0.5 0.7 0.9]

    foreach weight-values [ w-val ->
      ;; Create a list of parameter pairs
      let config (list
        (list "autonomy-level" 3)
        (list "start-prediction-weight" w-val)
      )
      set experiment-configs lput config experiment-configs
    ]
  ]

  ;; Add any additional custom configurations if specified
  if include-custom-configs? [
    ;; Example: Add a custom configuration with multiple parameters
    set experiment-configs lput (list
      (list "autonomy-level" 1)
      (list "cooperativeness-level" 0)
      (list "use-memory" true)
      (list "memory-fade" 5)
    ) experiment-configs

    set experiment-configs lput (list
      (list "autonomy-level" 1)
      (list "cooperativeness-level" 1)
      (list "use-memory" true)
      (list "memory-fade" 5)
    ) experiment-configs
  ]
end

;; Initialize the results data table
to initialize-results-table

  ;; Only proceed with foreach if we have configurations
  ifelse not empty? experiment-configs [
    foreach experiment-configs [ config ->
      let config-key config-to-string config
      table:put results-data config-key table:make
    ]
  ][
    ;; Handle case where there are no configurations
    print "Warning: No experiment configurations to initialize in results table."
  ]
end

;; Convert configuration to string key for table
to-report config-to-string [config]
  let result ""

  ;; First add all explicitly set parameters from the configuration
  foreach config [ param-pair ->
    set result (word result first param-pair "=" last param-pair "_")
  ]

  ;; Remove trailing underscore if it exists
  if not empty? result and last result = "_" [
    set result substring result 0 (length result - 1)
  ]

  report result
end

;; Generate a detailed configuration description for reporting
to-report detailed-config-description [config]
  let base-config config-to-string config

  ;; Add additional relevant parameters that might not be explicitly set in the config
  let detailed-config (word base-config "_")

  ;; Only add parameters not already in the config
  if not member? "courier-population" first-items config [
    set detailed-config (word detailed-config "couriers=" courier-population "_")
  ]

  if not member? "neighbourhood-size" first-items config [
    set detailed-config (word detailed-config "neighbourhood=" neighbourhood-size "_")
  ]

  if not member? "job-arrival-rate" first-items config [
    set detailed-config (word detailed-config "jobRate=" job-arrival-rate "_")
  ]

  if not member? "use-memory" first-items config [
    set detailed-config (word detailed-config "memory=" use-memory "_")
  ]

  if not member? "memory-fade" first-items config and use-memory [
    set detailed-config (word detailed-config "memoryFade=" memory-fade "_")
  ]

  if not member? "fade-strategy" first-items config and use-memory [
    set detailed-config (word detailed-config "fadeStrategy=" fade-strategy "_")
  ]

  if not member? "cooperativeness-level" first-items config [
    set detailed-config (word detailed-config "coop=" cooperativeness-level "_")
  ]

  if not member? "learning-model-chooser" first-items config and autonomy-level = 3 [
    set detailed-config (word detailed-config "learningModel=" learning-model-chooser "_")
  ]

  if not member? "start-prediction-weight" first-items config and
     autonomy-level = 3 and learning-model-chooser = "Demand Prediction" [
    set detailed-config (word detailed-config "predWeight=" start-prediction-weight "_")
  ]

  if not member? "restaurant-clusters" first-items config [
    set detailed-config (word detailed-config "clusters=" restaurant-clusters "_")
  ]

  if not member? "restaurants-per-cluster" first-items config [
    set detailed-config (word detailed-config "restsPerCluster=" restaurants-per-cluster "_")
  ]

  if not member? "restaurants-cluster-size" first-items config [
    set detailed-config (word detailed-config "restsClusterSize=" cluster-area-size "_")
  ]

  if not member? "opportunistic-switch" first-items config and autonomy-level = 3 [
    set detailed-config (word detailed-config "oppSwitch=" opportunistic-switch "_")
  ]

  if not member? "switch-threshold" first-items config and autonomy-level = 3 [
    set detailed-config (word detailed-config "switchThresh=" switch-threshold "_")
  ]

  ;; Remove trailing underscore
  if not empty? detailed-config and last detailed-config = "_" [
    set detailed-config substring detailed-config 0 (length detailed-config - 1)
  ]

  report detailed-config
end

;; Helper to get first items from each pair in a list of pairs
to-report first-items [pairs-list]
  let result []
  foreach pairs-list [ pair ->
    set result lput first pair result
  ]
  report result
end

;; Apply a configuration to the simulation
to setup-configuration [config]
  ;; Set the random seed based on configuration and run number
  let current-seed random-seed-base + current-run
  random-seed current-seed

  ;; Store experiment variables that need to be preserved
  let temp-experiment-running? experiment-running?
  let temp-experiment-completed? experiment-completed?
  let temp-experiment-configs experiment-configs
  let temp-current-config current-config
  let temp-current-run current-run
  let temp-max-runs max-runs
  let temp-run-ticks run-ticks
  let temp-random-seed-base random-seed-base
  let temp-results-data results-data
  let temp-data-export-path data-export-path

  ;; Clear the simulation without using clear-all
  clear-turtles
  clear-patches
  clear-drawing
  clear-all-plots
  clear-output

  ;; Restore experiment variables
  set experiment-running? temp-experiment-running?
  set experiment-completed? temp-experiment-completed?
  set experiment-configs temp-experiment-configs
  set current-config temp-current-config
  set current-run temp-current-run
  set max-runs temp-max-runs
  set run-ticks temp-run-ticks
  set random-seed-base temp-random-seed-base
  set results-data temp-results-data
  set data-export-path temp-data-export-path

  ;; Apply the configuration parameters
  foreach config [ param-pair ->
    let param-name first param-pair
    let param-value last param-pair

    run (word "set " param-name " " param-value)
  ]

  ;; Run the regular setup with these parameters
  ;; Call a modified setup procedure that doesn't use clear-all
  setup-for-experiment

  ;; Reset KPI tracking
  reset-kpis
end

;; Modified setup procedure that doesn't use clear-all
to setup-for-experiment
  ;; Initialize model without clearing globals
  ;; Copy the contents of your original setup procedure here,
  ;; but remove any clear-all or reset-ticks calls

  ;; Example (modify to match your actual setup procedure):
  set-default-shape turtles "bug"
  setup-restaurant-clusters
  setup-couriers

  ;; After creating restaurants and clusters, draw the connecting lines
  if show-cluster-lines? [
    draw-cluster-lines
  ]

  ;; Reset counters but preserve experiment variables
  set job-no 0
  set on-the-fly-jobs 0
  set memory-jobs 0
  set waiting-couriers 0
  set returning-couriers 0
  set delivering-couriers 0
  set searching-couriers 0

  ;; Reset-ticks is safe to call
  reset-ticks
end

;; Reset KPI tracking variables
to reset-kpis
  set total-deliveries 0
  set avg-delivery-time 0
  set delivery-times []
  set courier-utilization 0
  set waiting-time-total 0
  set search-time-total 0
  set delivery-pay-total 0
  set courier-earnings-sd 0
  set delivery-time-sd 0
  set courier-deliveries-sd 0
end

;; Run the experiment
to run-experiment
  if not experiment-running? [
    user-message "No experiment is set up. Please run setup-experiments first."
    stop
  ]

  if experiment-completed? [
    user-message "Experiment already completed. Please set up a new experiment."
    stop
  ]

  ;; Main experiment loop - continues until all configurations and runs are complete
  while [not empty? experiment-configs] [
    ;; Run the current configuration for the specified number of ticks
    repeat run-ticks [
      go

      ;; Update KPIs during run
      update-kpis
    ]

    ;; Collect data for this run
    collect-run-data

    ;; Check if we need to move to the next run or configuration
    ifelse current-run < max-runs [
      ;; Move to next run with the same configuration
      set current-run current-run + 1
      setup-configuration current-config
    ][
      ;; Move to the next configuration
      set experiment-configs but-first experiment-configs
      set current-run 1

      ;; If more configurations remain, set up the next one
      ifelse not empty? experiment-configs [
        set current-config first experiment-configs
        setup-configuration current-config
      ][
        ;; All experiments completed
        set experiment-completed? true
        set experiment-running? false
      ]
    ]
  ]

  ;; Export results when all experiments are complete
  export-results

  ;; Display completion message
  print "Experiment completed successfully."
  print (word "Results exported to: " data-export-path)
end

;; Update KPIs during a run
to update-kpis
  ;; Track courier statuses for utilization metrics
  let active-couriers count couriers with [status = "on-job"]
  let waiting-couriers-val count couriers with [status = "waiting-for-next-job"]
  let searching-couriers-val count couriers with [status = "searching-for-next-job"]

  ;; Update waiting and searching time totals
  set waiting-time-total waiting-time-total + waiting-couriers-val
  set search-time-total search-time-total + searching-couriers-val

  ;; Calculate instantaneous utilization
  let utilization 0
  if count couriers > 0 [
    set utilization active-couriers / count couriers
  ]

  ;; Update courier utilization (moving average)
  ifelse courier-utilization = 0 [
    set courier-utilization utilization
  ][
    set courier-utilization (courier-utilization * 0.95) + (utilization * 0.05)
  ]
end

;; Collect data at the end of a run
;; Collect data at the end of a run
to collect-run-data
  ;; Calculate final KPIs

  ;; Delivery completion metrics
  set total-deliveries length delivery-times

  ifelse not empty? delivery-times [
    set avg-delivery-time mean delivery-times
    set delivery-time-sd standard-deviation delivery-times
  ][
    set avg-delivery-time 0
    set delivery-time-sd 0
  ]

  ;; Courier earnings metrics
  let earnings []
  ask couriers [ set earnings lput total-reward earnings ]
  let avg-earnings 0
  ifelse not empty? earnings [
    set avg-earnings mean earnings
    set courier-earnings-sd standard-deviation earnings
  ][
    set avg-earnings 0
    set courier-earnings-sd 0
  ]

  ;; Deliveries per courier metrics
  let deliveries-per-courier []
  ask couriers [ set deliveries-per-courier lput length jobs-performed deliveries-per-courier ]
  let avg-deliveries-per-courier 0
  ifelse not empty? deliveries-per-courier [
    set avg-deliveries-per-courier mean deliveries-per-courier
    set courier-deliveries-sd standard-deviation deliveries-per-courier
  ][
    set avg-deliveries-per-courier 0
    set courier-deliveries-sd 0
  ]

  ;; Utilization percentages
  let total-courier-ticks count couriers * run-ticks
  let waiting-percentage 0
  let searching-percentage 0

  if total-courier-ticks > 0 [
    set waiting-percentage (waiting-time-total / total-courier-ticks) * 100
    set searching-percentage (search-time-total / total-courier-ticks) * 100
  ]

  ;; Calculate earnings per hour (1 tick = 1 second, so 3600 ticks = 1 hour)
  let earnings-per-hour 0
  if run-ticks > 0 [
    set earnings-per-hour (sum earnings) / (run-ticks / 3600)
  ]

  ;; NEW: Calculate job type metrics
  ;; Calculate ratio of on-the-fly jobs vs memory jobs
  let job-type-ratio 0
  if memory-jobs > 0 [
    set job-type-ratio on-the-fly-jobs / memory-jobs
  ]

  ;; Get ratio per courier if we're tracking per-courier
  let courier-job-type-ratios []
  let courier-on-the-fly-jobs []
  let courier-memory-jobs []
  let courier-total-jobs []

  ask couriers [
    ;; This would require tracking job types per courier
    ;; Here we're just tracking total jobs per courier
    let total-courier-jobs length jobs-performed
    set courier-total-jobs lput total-courier-jobs courier-total-jobs
  ]

  ;; Calculate average and SD of courier job counts
  let avg-jobs-per-courier 0
  let sd-jobs-per-courier 0

  ifelse not empty? courier-total-jobs [
    set avg-jobs-per-courier mean courier-total-jobs
    set sd-jobs-per-courier standard-deviation courier-total-jobs
  ][
    set avg-jobs-per-courier 0
    set sd-jobs-per-courier 0
  ]

  ;; Create results entry
  let config-key config-to-string current-config

  ;; Check if the key exists in the results table
  ifelse table:has-key? results-data config-key [
    let run-results table:get results-data config-key

    ;; Store results for this run
    table:put run-results (word "run_" current-run) (list
      total-deliveries
      avg-delivery-time
      delivery-time-sd
      avg-earnings
      courier-earnings-sd
      avg-deliveries-per-courier
      courier-deliveries-sd
      courier-utilization
      waiting-percentage
      searching-percentage
      earnings-per-hour
      on-the-fly-jobs            ;; NEW: Jobs found while searching
      memory-jobs                ;; NEW: Jobs found at restaurant
      job-type-ratio             ;; NEW: Ratio of on-the-fly to memory jobs
      avg-jobs-per-courier       ;; NEW: Average jobs per courier
      sd-jobs-per-courier        ;; NEW: Standard deviation of jobs per courier
    )

    ;; Update the results data
    table:put results-data config-key run-results
  ][
    ;; Handle the case where the key doesn't exist
    print (word "Error: Configuration key '" config-key "' not found in results table.")
    print "Available keys: "
    foreach table:keys results-data [ k ->
      print (word "  " k)
    ]

    ;; Create a new entry for this configuration
    let new-run-results table:make
    table:put new-run-results (word "run_" current-run) (list
      total-deliveries
      avg-delivery-time
      delivery-time-sd
      avg-earnings
      courier-earnings-sd
      avg-deliveries-per-courier
      courier-deliveries-sd
      courier-utilization
      waiting-percentage
      searching-percentage
      earnings-per-hour
      on-the-fly-jobs            ;; NEW: Jobs found while searching
      memory-jobs                ;; NEW: Jobs found at restaurant
      job-type-ratio             ;; NEW: Ratio of on-the-fly to memory jobs
      avg-jobs-per-courier       ;; NEW: Average jobs per courier
      sd-jobs-per-courier        ;; NEW: Standard deviation of jobs per courier
    )

    ;; Add to results data
    table:put results-data config-key new-run-results
  ]
end

;; Export results to a CSV file with enhanced configuration information
to export-results
  ;; Create headers for CSV with additional job metrics
  let csv-text "Configuration,DetailedConfiguration,Run,TotalDeliveries,AvgDeliveryTime,DeliveryTimeSD,AvgEarnings,EarningsSD,AvgDeliveriesPerCourier,DeliveriesPerCourierSD,CourierUtilization,WaitingPercentage,SearchingPercentage,EarningsPerHour,OnTheFlyJobs,MemoryJobs,JobTypeRatio,AvgJobsPerCourier,JobsPerCourierSD\n"

  ;; For each configuration
  foreach table:keys results-data [ config-key ->
    let config-results table:get results-data config-key

    ;; Find the original configuration object for this key
    let matching-config nobody
    foreach experiment-configs [ config ->
      if config-to-string config = config-key [
        set matching-config config
      ]
    ]

    ;; If config not found, create a placeholder
    if matching-config = nobody [
      ;; Try to parse the config key back into a config object
      set matching-config parse-config-string config-key
    ]

    ;; Generate detailed configuration description
    let detailed-config detailed-config-description matching-config

    ;; For each run of this configuration
    foreach table:keys config-results [ run-key ->
      let run-data table:get config-results run-key

      ;; Add line to CSV with explicit quotes around values
      set csv-text (word csv-text
        "\"" config-key "\",\""
        detailed-config "\","
        run-key ","
        item 0 run-data ",\""
        precision (item 1 run-data) 4 "\",\""
        precision (item 2 run-data) 4 "\",\""
        precision (item 3 run-data) 4 "\",\""
        precision (item 4 run-data) 4 "\",\""
        precision (item 5 run-data) 4 "\",\""
        precision (item 6 run-data) 4 "\",\""
        precision (item 7 run-data) 4 "\",\""
        precision (item 8 run-data) 4 "\",\""
        precision (item 9 run-data) 4 "\",\""
        precision (item 10 run-data) 4 "\","

        ;; Add new job metrics
        item 11 run-data ",\"" ;; OnTheFlyJobs
        item 12 run-data "\",\"" ;; MemoryJobs
        precision (item 13 run-data) 4 "\",\"" ;; JobTypeRatio
        precision (item 14 run-data) 4 "\",\"" ;; AvgJobsPerCourier
        precision (item 15 run-data) 4 "\"" ;; JobsPerCourierSD
        "\n"
      )
    ]
  ]

  ;; Write to file
  carefully [
    file-open data-export-path
    file-print csv-text
    file-close

    print (word "Results successfully exported to: " data-export-path)
    print "File can be imported into Excel or other analysis software."

    ;;verify-job-distribution

  ][
    print (word "Error writing to file: " error-message)
  ]
end

;; Helper to parse a config string back into a config object
to-report parse-config-string [config-string]
  let result []

  ;; Split by underscore
  let parts []
  let current-part ""
  let i 0

  ;; Parse each parameter pair from the string
  while [i < length config-string] [
    let char item i config-string

    ifelse char = "_" [
      ;; End of parameter pair
      if not empty? current-part [
        set parts lput current-part parts
        set current-part ""
      ]
    ][
      set current-part (word current-part char)
    ]

    set i i + 1
  ]

  ;; Add the last part if it exists
  if not empty? current-part [
    set parts lput current-part parts
  ]

  ;; Convert each part into a parameter pair
  foreach parts [ part ->
    let equals-pos position "=" part

    if equals-pos != false [
      let param-name substring part 0 equals-pos
      let param-value substring part (equals-pos + 1) (length part)

      ;; Try to convert value to appropriate type
      let typed-value param-value

      carefully [
        ;; Try to convert to number
        set typed-value read-from-string param-value
      ][
        ;; If conversion fails, keep as string
        if param-value = "true" [set typed-value true]
        if param-value = "false" [set typed-value false]
      ]

      set result lput (list param-name typed-value) result
    ]
  ]

  report result
end

;; Record delivery time when a job is completed
to record-delivery [job-tick]
  ;; Ensure delivery-times is initialized as a list
  if delivery-times = 0 or not is-list? delivery-times [
    set delivery-times []
  ]

  ;; Calculate completion time
  let completion-time ticks - job-tick

  ;; Add to list and update counter
  set delivery-times lput completion-time delivery-times
  set total-deliveries total-deliveries + 1
end

;; Calculate standard deviation
to-report standard-deviation-report [number-list]
  ;; Requires list to have at least two numbers
  if length number-list < 2 [
    report 0
  ]

  let avg mean number-list
  let variance-sum 0

  foreach number-list [ x ->
    set variance-sum variance-sum + (x - avg) ^ 2
  ]

  ;; Calculate sample standard deviation
  report sqrt (variance-sum / (length number-list - 1))
end

;; Helper function to get current date and time as a string
to-report date-and-time-report
  let date-string (word date-and-time "")
  ;; Replace spaces, colons and other characters that might be problematic in filenames
  set date-string replace-all date-string " " "_"
  set date-string replace-all date-string ":" "-"
  set date-string replace-all date-string "/" "-"
  report date-string
end

;; Helper to replace all instances of a substring
to-report replace-all [original-string search-string replace-string]
  let result original-string

  while [position search-string result != false] [
    let pos position search-string result
    let before-part substring result 0 pos
    let after-part substring result (pos + length search-string) (length result)
    set result (word before-part replace-string after-part)
  ]

  report result
end

;; Stop the current experiment
to stop-experiment
  set experiment-running? false
  print "Experiment stopped manually."
end

;; Add a reporter to find the cluster number for a location
to-report get-cluster-for-location [loc]
  let nearby-restaurant min-one-of restaurants [distance loc]
  if nearby-restaurant != nobody [
    report [cluster-number] of nearby-restaurant
  ]
  report -1  ;; Return -1 if no restaurant found
end

;; Procedure to track jobs per courier per cluster
to-report track-jobs-per-cluster [courier-agent]
  ;; Initialize a table to store jobs by cluster
  let cluster-jobs table:make

  ;; Initialize all clusters with zero jobs
  let cluster-count restaurant-clusters
  let i 0
  while [i < cluster-count] [
    table:put cluster-jobs i 0
    set i i + 1
  ]

  ;; Count jobs by cluster using the restaurant ID in jobs-performed
  foreach [jobs-performed] of courier-agent [ job-info ->
    let restaurant-id-val item 0 job-info

    ;; Find the restaurant by ID to get its cluster
    let restaurant-agent one-of restaurants with [restaurant-id = restaurant-id-val]

    if restaurant-agent != nobody [
      let cluster-num [cluster-number] of restaurant-agent

      let current-count 0
      if table:has-key? cluster-jobs cluster-num [
        set current-count table:get cluster-jobs cluster-num
      ]
      table:put cluster-jobs cluster-num (current-count + 1)
    ]
  ]

  report cluster-jobs
end

to-report track-jobs-per-restaurant [courier-agent]
  ;; Initialize a table to store jobs by restaurant ID
  let restaurant-jobs table:make

  ;; Count jobs by restaurant ID directly from jobs-performed
  foreach [jobs-performed] of courier-agent [ job-info ->
    let rest-id item 0 job-info

    let current-count 0
    if table:has-key? restaurant-jobs rest-id [
      set current-count table:get restaurant-jobs rest-id
    ]
    table:put restaurant-jobs rest-id (current-count + 1)
  ]

  report restaurant-jobs
end

;; Add a reporter to track earnings per cluster
to-report track-earnings-per-cluster [courier-agent]
  ;; Initialize a table to store earnings by cluster
  let cluster-earnings table:make

  ;; Initialize all clusters with zero earnings
  let cluster-count restaurant-clusters
  let i 0
  while [i < cluster-count] [
    table:put cluster-earnings i 0
    set i i + 1
  ]

  ;; Add up earnings by cluster
  foreach [jobs-performed] of courier-agent [ job-info ->
    let rest-id item 0 job-info
    let job-reward item 2 job-info

    ;; Find the restaurant by ID to get its cluster
    let restaurant-agent one-of restaurants with [restaurant-id = rest-id]

    if restaurant-agent != nobody [
      let cluster-num [cluster-number] of restaurant-agent

      let current-earnings 0
      if table:has-key? cluster-earnings cluster-num [
        set current-earnings table:get cluster-earnings cluster-num
      ]
      table:put cluster-earnings cluster-num (current-earnings + job-reward)
    ]
  ]

  report cluster-earnings
end

;; Add a reporter to track earnings per restaurant
to-report track-earnings-per-restaurant [courier-agent]
  ;; Initialize a table to store earnings by restaurant ID
  let restaurant-earnings table:make

  ;; Add up earnings by restaurant
  foreach [job-details] of courier-agent [ job-detail ->
    let restaurant-instance-val table:get job-detail "restaurant"
    let job-reward table:get job-detail "reward"

    if restaurant-instance != nobody [
      let rest-id [restaurant-id] of restaurant-instance-val

      let current-earnings 0
      if table:has-key? restaurant-earnings rest-id [
        set current-earnings table:get restaurant-earnings rest-id
      ]
      table:put restaurant-earnings rest-id (current-earnings + job-reward)
    ]
  ]

  report restaurant-earnings
end

;; Add this procedure to verify job distribution after the data is exported to CSV
to verify-job-distribution
  ;; Calculate and display job distribution statistics
  print "\n========== JOB DISTRIBUTION VERIFICATION ==========\n"

  ;; === BASIC STATISTICS ===
  ;; Total jobs and earnings (same as before)
  let total-jobs sum [length jobs-performed] of couriers
  print (word "Total jobs completed: " total-jobs)

  let total-earnings sum [total-reward] of couriers
  print (word "Total earnings: " precision total-earnings 2)

  ;; === RESTAURANT-BASED ANALYSIS ===
  print "\n=== RESTAURANT-BASED JOB DISTRIBUTION ===\n"

  ;; Create a global table of all restaurant jobs
  let global-restaurant-jobs table:make
  let total-restaurants restaurant-clusters * restaurants-per-cluster

  ;; Initialize all restaurants with zero jobs
  let i 1
  while [i <= total-restaurants] [
    table:put global-restaurant-jobs i 0
    set i i + 1
  ]

  ;; Count total jobs per restaurant across all couriers
  ask couriers [
    let courier-restaurant-jobs track-jobs-per-restaurant self

    ;; Add this courier's jobs to the global count
    foreach table:keys courier-restaurant-jobs [ rest-id ->
      let job-count table:get courier-restaurant-jobs rest-id
      let current-count 0

      if table:has-key? global-restaurant-jobs rest-id [
        set current-count table:get global-restaurant-jobs rest-id
      ]

      table:put global-restaurant-jobs rest-id (current-count + job-count)
    ]
  ]

  ;; Display jobs by restaurant
  print "Restaurant ID | Jobs Completed | Restaurant Cluster"
  print "-------------|----------------|------------------"

  foreach sort table:keys global-restaurant-jobs [ rest-id ->
    let job-count table:get global-restaurant-jobs rest-id

    ;; Find the restaurant's cluster
    let cluster-num "Unknown"
    let restaurant-agent one-of restaurants with [restaurant-id = rest-id]
    if restaurant-agent != nobody [
      set cluster-num [cluster-number] of restaurant-agent
    ]

    if job-count > 0 [
      print (word "      " rest-id "      |       " job-count "        |        " cluster-num)
    ]
  ]

  ;; === CLUSTER-BASED ANALYSIS ===
  print "\n=== CLUSTER-BASED JOB DISTRIBUTION ===\n"

  ;; Create a global table of all cluster jobs
  let global-cluster-jobs table:make
  let cluster-count restaurant-clusters

  ;; Initialize all clusters with zero jobs
  let j 0
  while [j < cluster-count] [
    table:put global-cluster-jobs j 0
    set j j + 1
  ]

  ;; Count total jobs per cluster across all couriers
  ask couriers [
    let courier-cluster-jobs track-jobs-per-cluster self

    ;; Add this courier's jobs to the global count
    foreach table:keys courier-cluster-jobs [ cluster-num ->
      let job-count table:get courier-cluster-jobs cluster-num
      let current-count 0

      if table:has-key? global-cluster-jobs cluster-num [
        set current-count table:get global-cluster-jobs cluster-num
      ]

      table:put global-cluster-jobs cluster-num (current-count + job-count)
    ]
  ]

  ;; Display jobs by cluster
  print "Cluster ID | Jobs Completed | % of Total Jobs"
  print "-----------|----------------|----------------"

  foreach sort table:keys global-cluster-jobs [ cluster-num ->
    let job-count table:get global-cluster-jobs cluster-num
    let percentage 0
    if total-jobs > 0 [
      set percentage (job-count / total-jobs) * 100
    ]

    print (word "     " cluster-num "     |       " job-count "        |     " precision percentage 2 "%")
  ]

  ;; === COURIER JOB DISTRIBUTION BY CLUSTER ===
  print "\n=== COURIER JOB DISTRIBUTION BY CLUSTER ===\n"

  ;; Create header row for the table
  let header-str "Courier ID | "
  let k 0
  while [k < cluster-count] [
    set header-str (word header-str "Cluster " k "   ")
    set k k + 1
  ]
  print header-str

  ;; Create separator row
  let separator-str "----------|"
  set k 0
  while [k < cluster-count] [
    set separator-str (word separator-str "-----------")
    set k k + 1
  ]
  print separator-str

  ;; Show each courier's job distribution by cluster
  ask couriers [
    let courier-cluster-jobs track-jobs-per-cluster self
    let courier-row (word "    " who "     |")

    let m 0
    while [m < cluster-count] [
      let job-count 0
      if table:has-key? courier-cluster-jobs m [
        set job-count table:get courier-cluster-jobs m
      ]

      set courier-row (word courier-row "     " job-count "     ")
      set m m + 1
    ]

    print courier-row
  ]

  ;; === COURIER EARNINGS DISTRIBUTION BY CLUSTER ===
  if any? couriers with [not empty? jobs-performed] [
    print "\n=== COURIER EARNINGS DISTRIBUTION BY CLUSTER ===\n"

    ;; Create header row for the table
    let earnings-header-str "Courier ID | "
    let n 0
    while [n < cluster-count] [
      set earnings-header-str (word earnings-header-str "Cluster " n "   ")
      set n n + 1
    ]
    print earnings-header-str

    ;; Create separator row
    let earnings-separator-str "----------|"
    set n 0
    while [n < cluster-count] [
      set earnings-separator-str (word earnings-separator-str "-----------")
      set n n + 1
    ]
    print earnings-separator-str

    ;; Show each courier's earnings distribution by cluster
    ask couriers [
      let courier-cluster-earnings track-earnings-per-cluster self
      let courier-row (word "    " who "     |")

      let p 0
      while [p < cluster-count] [
        let earnings 0
        if table:has-key? courier-cluster-earnings p [
          set earnings table:get courier-cluster-earnings p
        ]

        set courier-row (word courier-row "   " precision earnings 1 "   ")
        set p p + 1
      ]

      print courier-row
    ]
  ]

  ;; === ALGORITHM EFFECTIVENESS ANALYSIS ===
  if cooperativeness-level = 1 [
    print "\n=== ALGORITHM EFFECTIVENESS ANALYSIS ===\n"
    print (word "Job sharing algorithm used: " job-sharing-algorithm)

    ;; Calculate cluster-specific statistics
    foreach sort table:keys global-cluster-jobs [ cluster-num ->
      let cluster-job-counts []
      let cluster-courier-ids []

      ask couriers [
        let courier-cluster-jobs track-jobs-per-cluster self
        if table:has-key? courier-cluster-jobs cluster-num [
          let job-count table:get courier-cluster-jobs cluster-num
          if job-count > 0 [
            set cluster-job-counts lput job-count cluster-job-counts
            set cluster-courier-ids lput who cluster-courier-ids
          ]
        ]
      ]

      ;; Only analyze if we have enough data
      ifelse length cluster-job-counts >= 2 [
        print (word "\nCluster " cluster-num " Analysis:")

        ;; Calculate basic statistics
        let avg-jobs mean cluster-job-counts
        let std-dev-jobs standard-deviation cluster-job-counts
        let cv-jobs 0
        if avg-jobs > 0 [
          set cv-jobs std-dev-jobs / avg-jobs
        ]

        print (word "  Average jobs per courier: " precision avg-jobs 2)
        print (word "  Standard deviation: " precision std-dev-jobs 2)
        print (word "  Coefficient of variation: " precision cv-jobs 3 " (lower is more even)")

        ;; Algorithm-specific analysis
        ifelse job-sharing-algorithm = "Balanced Load" and length cluster-job-counts >= 3 [
          let correlation calculate-correlation cluster-courier-ids cluster-job-counts

          print (word "  Balanced Load effectiveness - Correlation: " precision correlation 3)
          ifelse correlation < 0.3 [
            print "    Low correlation suggests effective load balancing"
          ][
            ifelse correlation < 0.7 [
            print "    Moderate correlation suggests partial load balancing"
          ][
            print "    High correlation suggests minimal load balancing"
          ]
        ]
        ]
        [
          if job-sharing-algorithm = "Proportional Fairness" and any? couriers with [not empty? jobs-performed] [
            ;; For proportional fairness, we need to check if earnings distribution is more even than job distribution
            let cluster-earnings []

            ask couriers [
              let courier-cluster-earnings track-earnings-per-cluster self
              if table:has-key? courier-cluster-earnings cluster-num [
                let earnings table:get courier-cluster-earnings cluster-num
                if earnings > 0 [
                  set cluster-earnings lput earnings cluster-earnings
                ]
              ]
            ]

            if length cluster-earnings >= 2 [
              let avg-earnings mean cluster-earnings
              let std-dev-earnings standard-deviation cluster-earnings
              let cv-earnings 0
              if avg-earnings > 0 [
                set cv-earnings std-dev-earnings / avg-earnings
              ]

              print (word "  Proportional Fairness effectiveness:")
              print (word "    Job distribution CV: " precision cv-jobs 3)
              print (word "    Earnings distribution CV: " precision cv-earnings 3)

              ifelse cv-earnings < cv-jobs [
                print "    Earnings are more evenly distributed than jobs, suggesting the algorithm worked as intended"
              ]
              [
                print "    Earnings distribution is not more even than job distribution, suggesting the algorithm may not have been fully effective"
              ]
            ]
          ]
        ]
        ]
        [
          print (word "\nCluster " cluster-num ": Not enough couriers with jobs for statistical analysis")
        ]

  ]
  ]

  print "\n========== END VERIFICATION ==========\n"
end

;; Helper function to calculate correlation between two lists
to-report calculate-correlation [list1 list2]
  let n length list1

  ;; Ensure lists are the same length
  if n != length list2 [
    report 0  ;; Return 0 if lists are different lengths
  ]

  ;; Calculate means
  let mean1 mean list1
  let mean2 mean list2

  ;; Calculate sum of products of deviations
  let sum-of-products 0
  let sum-of-squares1 0
  let sum-of-squares2 0

  let i 0
  while [i < n] [
    let dev1 (item i list1) - mean1
    let dev2 (item i list2) - mean2

    set sum-of-products sum-of-products + (dev1 * dev2)
    set sum-of-squares1 sum-of-squares1 + (dev1 * dev1)
    set sum-of-squares2 sum-of-squares2 + (dev2 * dev2)

    set i i + 1
  ]

  ;; Calculate correlation coefficient
  ifelse sum-of-squares1 > 0 and sum-of-squares2 > 0 [
    report sum-of-products / (sqrt sum-of-squares1 * sqrt sum-of-squares2)
  ][
    report 0  ;; Handle case where variance is zero
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
738
539
-1
-1
8.0
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
113
10
176
43
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
6.0
1
1
NIL
HORIZONTAL

SLIDER
15
509
187
542
job-arrival-rate
job-arrival-rate
0
100
3.0
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
1516
10
1890
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
2.0
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
3.0
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
8.0
1
1
NIL
HORIZONTAL

SLIDER
11
210
183
243
level-of-order
level-of-order
0
100
12.0
1
1
NIL
HORIZONTAL

SWITCH
11
168
140
201
use-memory
use-memory
0
1
-1000

SLIDER
11
251
183
284
memory-fade
memory-fade
0
20
5.0
0.5
1
%
HORIZONTAL

PLOT
1545
347
1890
527
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
"pen-1" 1.0 0 -2674135 true "" "plot count jobs"

PLOT
1542
169
1890
338
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
781
511
889
556
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
0
3
2.0
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
0
3
1.0
1
1
NIL
HORIZONTAL

SWITCH
442
549
592
582
show-cluster-lines
show-cluster-lines
0
1
-1000

CHOOSER
11
291
162
336
fade-strategy
fade-strategy
"None" "Linear" "Exponential" "Recency-weighted"
1

SLIDER
11
342
183
375
free-moving-threshold
free-moving-threshold
0
50
10.0
1
1
NIL
HORIZONTAL

CHOOSER
12
401
189
446
learning-model-chooser
learning-model-chooser
"Demand Prediction" "Learning and Adaptation"
0

SLIDER
14
459
186
492
learning-rate
learning-rate
0.1
1
0.2
0.1
1
NIL
HORIZONTAL

SWITCH
781
169
915
202
debug-memory
debug-memory
1
1
-1000

SWITCH
782
217
971
250
debug-demand-prediction
debug-demand-prediction
1
1
-1000

SWITCH
20
556
179
589
first-go-back-to-rest
first-go-back-to-rest
1
1
-1000

SWITCH
216
562
374
595
opportunistic-switch
opportunistic-switch
0
1
-1000

SLIDER
392
624
564
657
switch-threshold
switch-threshold
10
100
10.0
5
1
%
HORIZONTAL

SLIDER
785
122
957
155
debug-interval
debug-interval
0
600
60.0
60
1
NIL
HORIZONTAL

SLIDER
680
589
852
622
start-prediction-weight
start-prediction-weight
0
1
1.0
0.05
1
NIL
HORIZONTAL

MONITOR
902
517
1082
562
Prediction Weights
all-prediction-weights
2
1
11

MONITOR
916
460
997
505
Time of Day
get-current-time-block
2
1
11

MONITOR
780
456
905
501
Prediction Accuracy
prediction-accuracy
2
1
11

PLOT
29
700
229
850
Courier Rewards
Time (ticks)
Earnings
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "ifelse ticks > earnings-update-interval [plot mean earnings-per-interval][plot 0]"

PLOT
1545
537
1890
687
Courier Cumulative Earnings
Time (ticks)
Total Earnings
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "ifelse ticks >= 3600 [plot mean [total-reward / (ticks / 3600)] of couriers][plot 0]"

PLOT
399
687
599
837
Prediction Accuracy
Ticks (time)
Accuracy (%)
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if prediction-accuracy > 0 [plot prediction-accuracy]"

SLIDER
1135
41
1323
74
experiment-runs-per-config
experiment-runs-per-config
1
50
15.0
1
1
NIL
HORIZONTAL

SLIDER
1135
76
1373
109
experiment-ticks-per-run
experiment-ticks-per-run
3600
432000
86400.0
3600
1
seconds
HORIZONTAL

SLIDER
1135
112
1307
145
experiment-base-seed
experiment-base-seed
1
999
1.0
1
1
NIL
HORIZONTAL

SWITCH
1135
183
1276
216
vary-autonomy?
vary-autonomy?
0
1
-1000

SWITCH
1135
218
1306
251
vary-cooperativeness?
vary-cooperativeness?
0
1
-1000

SWITCH
1135
253
1266
286
vary-memory?
vary-memory?
1
1
-1000

SWITCH
1135
287
1314
320
vary-prediction-weight?
vary-prediction-weight?
1
1
-1000

SWITCH
1135
322
1314
355
include-custom-configs?
include-custom-configs?
1
1
-1000

BUTTON
1135
382
1262
415
Setup Experiments
setup-experiments
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
1135
418
1253
451
Run Experiments
run-experiment
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
1135
454
1256
487
Stop Experiments
stop-experiment
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
1146
513
1399
573
analysis-file-path
C:\\Users\\deazb\\Documents\\GitHub\\self-organizing-crowdsourced-food-delivery-system\\experiments
1
0
String

BUTTON
1171
602
1281
635
Analyze Results
analyze-experiment-results analysis-file-path
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1004
642
1204
792
Autonomy Level Comparison
Autonomy Level
Value
0.0
3.0
0.0
10.0
true
false
"" ""
PENS
"Deliveries" 1.0 0 -16777216 true "" ""
"Earnings" 1.0 0 -7500403 true "" ""
"Utilization" 1.0 0 -2674135 true "" ""

PLOT
1211
645
1411
795
Performance Variability
Autonomy Level
Variability
0.0
3.0
0.0
10.0
true
false
"" ""
PENS
"Earnings Var" 1.0 0 -16777216 true "" ""
"Time Var" 1.0 0 -7500403 true "" ""
"Deliveries Var" 1.0 0 -2674135 true "" ""

CHOOSER
60
649
309
694
job-sharing-algorithm
job-sharing-algorithm
"Balanced Load" "Proportional Fairness"
0

SWITCH
965
175
1081
208
debug-coop
debug-coop
1
1
-1000

SLIDER
711
668
914
701
strategic-repositioning-interval
strategic-repositioning-interval
60
60
60.0
60
1
NIL
HORIZONTAL

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

### Memory fade

For each memory fade algorithm, the suitable values for the memory-fade parameter will differ based on how aggressively each algorithm applies the fade. Note that this is also connected to the the instance (e.g., job arrival rate, number of restaurants). If the instance does not generate enough demand, the memory of each courier is not updated frequently, resulting in reaching the free-moving threshold earlier. Also the cluster size and neigbourhood-size is important (if coop > 0). If the cluster is too disperse and/or the neighbourhood size too small, couriers remain at a single restaurant, not getting frequent new entries into their memory. 


Here are recommended ranges for each strategy:

#### Linear Fade
- **Range**: 0.5% - 10%
- **Typical values**: 1-5%
- **Explanation**: Since linear fade applies the same reduction to all memories, even small values can have a significant cumulative effect over time. Values above 10% may cause memories to fade too quickly.

#### Exponential Fade
- **Range**: 1% - 15%
- **Typical values**: 3-8%
- **Explanation**: Since the algorithm applies stronger decay to older memories while preserving newer ones, you can use slightly higher values than with linear fade. The exponential effect makes older memories fade quickly even with moderate parameter values.

#### Recency-weighted Fade
- **Range**: 2% - 20%
- **Typical values**: 5-12%
- **Explanation**: This algorithm is designed to strongly preserve recent memories while allowing older ones to fade more rapidly. It can handle higher fade rates without losing important recent information.

#### When to use different values:

- **Low values** (0.5-3%): Use when you want memories to persist for a long time, creating couriers with long-term stable behaviors.

- **Medium values** (3-10%): Good balanced approach for most simulations, allowing gradual adaptation while maintaining some history.

- **High values** (10-20%): Use when you want couriers to adapt quickly to changing conditions, with little influence from older experiences.

When experimenting, I recommend starting with these values:
- Linear: 2%
- Exponential: 5%
- Recency-weighted: 8%

Then adjust based on how quickly you want memories to fade in your specific simulation scenario. The debug output will help you visualize how different values affect the memory over time.

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
