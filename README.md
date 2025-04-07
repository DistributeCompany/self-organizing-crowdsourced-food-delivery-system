# 🚲 Self-Organization in Crowdsourced Food Delivery Systems

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NetLogo](https://img.shields.io/badge/NetLogo-6.4.0-blue.svg)](http://ccl.northwestern.edu/netlogo/)

An agent-based simulation model in NetLogo to study self-organization in crowdsourced food delivery systems. This model explores how varying levels of courier autonomy and cooperation impact system performance, workload balance, and responsiveness to changing demand patterns.

## 🎯 Features

- Multi-agent system with couriers, restaurants, customers, and dynamic job creation
- Configurable autonomy levels affecting courier decision-making
- Cooperative behavior between couriers with information sharing
- Memory-based learning for optimal restaurant selection
- Dynamic reward system based on delivery distances
- Cluster-based restaurant distribution
- Real-time visualization of courier activities

## 🔧 Parameters

### Main Controls
- `autonomy-level`: (0-3) Determines how independently couriers make decisions
  - Level 0: No autonomy (dedicated restaurant service)
  - Level 1: Low autonomy (local job acceptance)
  - Level 2: Medium autonomy (strategic repositioning)
  - Level 3: High autonomy (active opportunity search)
- `cooperativeness-level`: (0-3) Controls information sharing between couriers
  - Level 0: No cooperation (independent operation)
  - Level 1: Low cooperation (local job sharing)
  - Level 2: Medium cooperation (restaurant occupancy information)
  - Level 3: High cooperation (heatmap sharing)
- `bike-population`: Number of courier agents in the simulation
- `restaurant-clusters`: Number of restaurant groupings
- `restaurants-per-cluster`: Number of restaurants in each cluster
- `cluster-area-size`: Physical size of restaurant clusters
- `job-arrival-rate`: Frequency of new delivery orders
- `memory-fade`: Rate at which courier memory of past rewards decays
- `fade-strategy`: Memory decay algorithm (Linear, Exponential, Recency-weighted)
- `neighbourhood-size`: Radius for couriers to detect nearby jobs
- `use-memory`: Toggle for memory-based decision making
- `free-moving-threshold`: Minimum expected reward to remain at location
- `random-startingpoint-bikes`: Toggle for random vs restaurant-based courier starting positions
- `job-sharing-algorithm`: Method for job assignment (Balanced Load or Proportional Fairness)
- `ego-level`: Weight on personal experiences versus colleagues' shared information

## 🎨 Agent States

### Couriers
- 🟢 Green: Searching for next job
- 🟡 Orange: Waiting for next job at restaurant
- 🔴 Red: Actively delivering an order
- 🔵 Blue: Moving towards a restaurant
- ⚫ Grey: En route to pickup location

### Other Agents
- 🏠 White: Available restaurant
- 🏠 Brown: Restaurant with active order
- 👤 Cyan: Customer with pending delivery
- 🏠 Brown (small): Active job
- 🏠 Red: Restaurant cluster center

## 📊 Metrics

The simulation tracks several key performance indicators:
- Total rewards per courier
- Jobs completed per restaurant
- Courier activity distribution
- Workload balance (standard deviation of jobs per courier)
- Average and maximum number of open orders
- Delivery times and service levels
- Efficiency-to-balance ratio
- System responsiveness to demand fluctuations

## 🚀 Getting Started

1. Install [NetLogo 6.4.0](http://ccl.northwestern.edu/netlogo/) or later
2. Download the model file (`crowdsourced-delivery-sim.nlogo`)
3. Open the model in NetLogo
4. Click "Setup" to initialize the simulation
5. Use "Go" to run the simulation

## 📖 Implementation Details

### Environment
- Two-dimensional grid (default 65x65)
- Restaurant clusters with configurable density
- Time-based demand patterns across four daily periods

### Time-Based Demand Distribution
- 00:00-09:00: 6% of daily demand
- 09:00-17:30: 41% of daily demand
- 17:30-20:00: 33% of daily demand
- 20:00-24:00: 20% of daily demand

### Memory System
The model implements three memory fade mechanisms:
- Linear fade: Applies constant reduction to all memories
- Exponential fade: Stronger decay for older memories
- Recency-weighted fade: Preserves recent memories, rapidly fades older ones

## 🔍 Key Findings

Our simulation results indicate:
- Medium-to-high autonomy with low-to-moderate cooperation yields the best workload balance
- Low cooperation consistently underperforms regardless of autonomy settings
- Higher cooperation generally improves system performance, though with diminishing returns
- Low autonomy significantly increases both average and peak numbers of open orders
- Increasing autonomy and cooperation enhances system robustness to demand fluctuations

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📚 Citation

If you use this model in your research, please cite:
```bibtex
@misc{gerrits2025self,
  author = {Gerrits, Berry and Mes, Martijn},
  title = {Self-Organization in Crowdsourced Food Delivery Systems Simulation},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/DistributeCompany/self-organizing-crowdsourced-food-delivery-system}
}
```

## 🙏 Acknowledgments

- NetLogo team at Northwestern University
- Department of High Tech Business and Entrepreneurship, University of Twente