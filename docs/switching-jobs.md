# Opportunistic vs. Non-Opportunistic Job Switching

The simulation implements two different approaches for couriers to take or switch jobs: opportunistic and non-opportunistic. This distinction appears primarily in the `re-evaluate-route-based-on-prediction` procedure, which determines whether couriers should switch from their current job to a newly discovered one, or take a job when they're not currently assigned to one. Taking or switching jobs is only relevant when the following conditions are met:

- The status of the courier is `moving-towards-restaurant` 
- The autonomy level is set to `level 3`
- The `learning-model` is set to `Demand Prediction`
- The parameter `first-go-back-to-restaurant` is set to `False`

Potential jobs available to take or switch to are always determined by the value of `neighbourhood-size`

## Common Initial Threshold: `switch-threshold`

Both opportunistic and non-opportunistic modes first apply the `switch-threshold` parameter to determine if a new job is significantly better than the current one:

```netlogo
;; Only consider jobs with significantly better reward
ifelse [reward] of best-job > current-reward * (1 + switch-threshold / 100) [
  ;; Consider switching...
][
  ;; Not significantly better, don't switch
    print (word "  NOT SWITCHING: New job reward not significantly better (needs " switch-threshold "% improvement)")
]
```

For example, if `switch-threshold` is set to 30, a new job must offer at least 30% more reward than the current job before the courier will consider switching.

## Opportunistic Switching

When `opportunistic-switch` is enabled, couriers will always take a newly discovered job if it passes the initial `switch-threshold` check, without considering the expected value of the restaurant it is returning to (if any).

### Taking a New Job (No Current Job)

```netlogo
;; Always take best job if opportunistic switching is enabled
ifelse opportunistic-switch [
  print (word "  TAKING JOB: Opportunistic switching enabled, taking best job #" [who] of best-job)

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
]
```

This snippet shows that when `opportunistic-switch` is true and the courier doesn't have a current job, they immediately take the best job they found in their neighborhood without any additional considerations.

### Switching Jobs (Already Has a Job)

When a courier already has a job but discovers a potentially better one:

```netlogo
;; Evaluate whether to switch based on opportunistic-switch or value comparison
ifelse opportunistic-switch [
  ;; Always switch if opportunistic and the job passes the switch-threshold
    print (word "  SWITCHING JOBS: Opportunistic switching enabled")

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
]
```

With opportunistic switching, after passing the initial `switch-threshold` check, the courier will immediately abandon their current job (making it available again) and take the new one regardless of how much progress they've made on the current delivery.

## Non-Opportunistic Switching

When `opportunistic-switch` is false, couriers make more sophisticated decisions, weighing costs and benefits before switching or taking jobs.

### Taking a New Job (No Current Job)

```netlogo
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
  ]
]

;; Compare best job to current destination value
ifelse (not returning-to-restaurant?) or ([reward] of best-job > current-restaurant-value * (1 + switch-threshold / 100)) [
  ;; Take job if it's better than current destination or we're not returning anywhere specific
  ;; ... job taking code ...
][
  ;; Don't take job, continue to current destination
]
```

In non-opportunistic mode, when considering taking a new job, the courier first checks if they're currently heading back to a restaurant and calculates the expected value of that restaurant. The courier only takes the new job if it passes the initial `switch-threshold`, or if they're not heading to a specific restaurant.

### Switching Jobs (Already Has a Job)

```netlogo
;; Only consider jobs with significantly better reward
ifelse [reward] of best-job > current-reward * (1 + switch-threshold / 100) [
  ;; Calculate switching cost (progress lost on going to origin of current job)
  let origin-to-dest-distance (distance [origin] of current-job + distance [destination] of current-job)
  let progress-so-far distance [destination] of current-job / origin-to-dest-distance
  let switching-cost current-reward * progress-so-far

  ;; Evaluate whether to switch based on opportunistic-switch or value comparison
  ifelse opportunistic-switch [
    ;; Always switch if opportunistic
    ;; ... switching code ...
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
      
      ;; ... switching code ...
    ][
      ;; Not worth switching - continue with current job
    ]
  ]
][
  ;; New job not significantly better - don't even consider switching
]
```

In non-opportunistic mode, switching jobs involves a more sophisticated calculation after passing the initial `switch-threshold` check:

1. The courier calculates how much progress they've made on the current delivery
2. The "switching cost" is calculated as the progress percentage multiplied by the current job's reward
3. The courier compares the new job's reward with the sum of the switching cost and the current reward
4. The courier only switches if the new job is worth more than what they would effectively lose by abandoning the current job

## Key Differences: Summary

1. **Both approaches**:
   - Apply the `switch-threshold` parameter as an initial filter
   - Only consider jobs that are significantly better (by the threshold percentage)

2. **Opportunistic approach**:
   - If a job passes the threshold check, immediately switches
   - Ignores progress made on current deliveries

3. **Non-opportunistic approach**:
   - If a job passes the threshold check, performs additional cost-benefit analysis
   - Calculates switching costs based on progress made
   - Makes more economically rational decisions