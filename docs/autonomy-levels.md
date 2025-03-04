# Autonomous Bike Courier Simulation: Autonomy Levels

This document explains the four levels of autonomy (0-3) implemented in the bike courier simulation model. Each level represents increasing decision-making capabilities for courier agents.

## Autonomy Level Overview

The model uses the `autonomy-level` slider to set how independently couriers make decisions. Higher levels grant couriers more sophisticated decision-making abilities.

| Level | Name | Description |
|-------|------|-------------|
| 0 | Restricted | Couriers only accept jobs from their assigned restaurant |
| 1 | Low | Couriers always return to the same restaurant after delivery |
| 2 | Medium | Couriers make basic adaptive decisions to change locations |
| 3 | High | Couriers use advanced prediction models or learning algorithms |

## Detailed Explanation

### Level 0: Restricted Autonomy

At the most basic level, couriers have severely limited decision-making abilities:

- Couriers only accept jobs from the **exact same restaurant** they've delivered for previously
- If `random-start-point-courier` is `On`, this is the first restaurant with a job a courier encounters after setup
- If `random-start-point-courier` is `Off`, this is the restaurant the courier is assigned to at the setup
- After completing a delivery, they immediately return to their assigned restaurant
- They do not explore new areas or consider jobs from other restaurants
- If no jobs are available at their restaurant, they simply wait

This level simulates a central assignment, with dedicated couriers per restaurant and where couriers have no flexibility in job selection.

### Level 1: Low Autonomy

Similar to Level 0, with slightly more freedom, couriers can:

- Accept jobs within their neighbourhood radius while at a restaurant (only if status is `waiting-for-next-job`)
- Always return to their previous restaurant after completing a delivery
- If no jobs are available in the neighbourhood, they simply wait

Level 1 couriers follow predictable patterns with some degree of freedom to accept jobs in the neighbourhood of their current location in case of no demand. 

### Level 2: Medium Autonomy

Similar to Level 1, but couriers gain basic adaptive decision-making:

- Couriers track historical performance by restaurant
- Will abandon waiting at a restaurant if the expected average reward of the neighbourhood falls below the `free-moving-threshold`

Note: Set `use-memory` to `On` with `memory-fade` set to non-zero, for level 2 to work properly. At this level, couriers 'get sick of waiting', but have no decision-making capabilities to determine where to go and resort to a random search. 


### Level 3: High Autonomy

Similar to Level 2, but with advanced decision-making capabilities. 

#### When using "Demand Prediction" learning model:
- Couriers track historical performance by restaurant AND time of day
- Maintain a "heat map" of locations scored by multiple factors:
  - Predicted demand based on recent history and temporal performance
  - Distance to restaurants
  - Competition from other couriers (if `cooperativeness-level` > 0)

- Will relocate to a more promising restaurant, if the expected average reward of the current restaurant falls below the `free-moving-threshold`. If there are no promising restaurants, resort to a random search. 

- Can opportunistically switch jobs if better opportunities arise in the neighbourhood (also when on the road)

#### When using "Learning and Adaptation" learning model:
- Uses reinforcement learning to adapt to changing conditions (placeholder in current implementation)
- Would involve the `apply-reinforcement-learning` and related procedures
- Designed to make dynamic adjustments based on outcomes of previous decisions

Level 3 couriers simulate truly intelligent agents that can balance multiple factors and predict future outcomes.

## Key Parameters Affecting Autonomy

Several parameters influence how effectively couriers use their autonomy:

- `use-memory`: Enables couriers to remember past rewards (required for levels 2 and 3)
- `memory-fade`: Controls how quickly past experiences are forgotten
- `fade-strategy`: Determines how memory fades over time (linear, exponential, etc.)
- `free-moving-threshold`: Sets the minimum expected reward before couriers will move from a restaurant (for levels 2 and 3)
- `learning-rate`: Affects how quickly couriers adapt to new information (for Level 3)
- `prediction-weight`: Balances historical patterns vs. recent events in decision-making (for Level 3)
- `switch-threshold`: Percentage improvement needed before switching to a better job (for Level 3)