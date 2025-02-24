# 🚲 Self-Organization in Crowdsourced Food Delivery Systems Simulation

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NetLogo](https://img.shields.io/badge/NetLogo-6.3.0-blue.svg)](http://ccl.northwestern.edu/netlogo/)

An agent-based simulation model in Netlogo to study self-organizing in crowdsourced food delivery systems.

## 🎯 Features

- Multi-agent system with bikes, restaurants, customers, and dynamic job creation
- Configurable autonomy levels affecting courier decision-making
- Cooperative behavior between couriers with information sharing
- Memory-based learning for optimal restaurant selection
- Dynamic reward system based on delivery distances
- Cluster-based restaurant distribution
- Real-time visualization of courier activities

## 🔧 Parameters

### Main Controls
- `autonomy-level`: (1-3) Determines how independently couriers make decisions
- `cooperativeness-level`: (1-3) Controls information sharing between couriers
- `bike-population`: Number of courier agents in the simulation
- `restaurant-clusters`: Number of restaurant groupings
- `restaurants-per-cluster`: Number of restaurants in each cluster
- `cluster-area-size`: Physical size of restaurant clusters
- `job-arrival-rate`: Frequency of new delivery orders
- `memory-fade`: Rate at which courier memory of past rewards decays
- `neighbourhood-size`: Radius for couriers to detect nearby jobs
- `use-memory`: Toggle for memory-based decision making
- `random-startingpoint-bikes`: Toggle for random vs restaurant-based courier starting positions

## 🎨 Agent States

### Bike Couriers
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
- Memory-based restaurant preferences
- On-the-fly vs memory-based job acceptance

## 🚀 Getting Started

1. Install [NetLogo 6.4.0](http://ccl.northwestern.edu/netlogo/) or later
2. Download the model file (`crowdsourced-delivery-sim.nlogo`)
3. Open the model in NetLogo
4. Click "Setup" to initialize the simulation
5. Use "Go" to run the simulation

## 📖 Implementation Details

### Agent Types
- **Bikes**: Autonomous courier agents that pick up and deliver orders
- **Restaurants**: Static agents that generate delivery jobs
- **Customers**: Temporary agents representing delivery destinations
- **Clusters**: Centers of restaurant groupings
- **Jobs**: Dynamic agents representing active delivery orders

### Decision Making
The model implements three levels of autonomy:
1. **Low**: Couriers follow simple rules and stay near assigned restaurants
2. **Medium**: Couriers use memory but remain conservative in decisions
3. **High**: Couriers actively evaluate and adjust routes based on rewards

Cooperation levels affect how couriers share information:
1. **Low**: No information sharing
2. **Medium**: Limited local information exchange
3. **High**: Full cooperation with job handoffs

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📚 Citation

If you use this model in your research, please cite:
```bibtex
@misc{autonomous-bike-courier-sim,
  author = {[Berry Gerrits]},
  title = {Self-Organization in Crowdsourced Food Delivery Systems Simulation},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/yourusername/autonomous-bike-courier-sim}
}
```

## 🙏 Acknowledgments

- NetLogo team at Northwestern University
- Contributors to the Extensions API
- [Your additional acknowledgments]