import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import sys
import re
import os
from datetime import datetime
from scipy import stats
import itertools

def load_and_parse_csv(file_path):
    """
    Load the CSV file and perform initial parsing of data
    """
    print(f"Loading data from {file_path}...")
    try:
        # Read CSV file
        df = pd.read_csv(file_path)
        
        # Convert Run column to a proper format (run_X -> X)
        df['Run'] = df['Run'].apply(lambda x: int(x.split('_')[1]) if isinstance(x, str) and '_' in x else x)
        
        # Clean up numeric columns (remove quotes if present)
        numeric_columns = [
            'TotalDeliveries', 'AvgDeliveryTime', 'DeliveryTimeSD', 
            'AvgEarnings', 'EarningsSD', 'AvgDeliveriesPerCourier',
            'DeliveriesPerCourierSD', 'CourierUtilization', 'WaitingPercentage',
            'SearchingPercentage', 'EarningsPerHour', 'OnTheFlyJobs',
            'MemoryJobs', 'JobTypeRatio', 'AvgJobsPerCourier', 'JobsPerCourierSD',
            # New open orders metrics
            'AvgOpenOrders', 'MaxOpenOrders',
            'CreatedWindow1', 'CreatedWindow2', 'CreatedWindow3', 'CreatedWindow4',
            'CompletedWindow1', 'CompletedWindow2', 'CompletedWindow3', 'CompletedWindow4'
        ]
        
        for col in numeric_columns:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        
        # Extract key parameters from Configuration
        df['AutonomyLevel'] = df['Configuration'].apply(
            lambda x: extract_parameter(x, 'autonomy-level')
        )
        
        df['CooperativenessLevel'] = df['Configuration'].apply(
            lambda x: extract_parameter(x, 'cooperativeness-level')
        )
        
        df['UseMemory'] = df['Configuration'].apply(
            lambda x: extract_parameter(x, 'use-memory', is_bool=True)
        )
        
        df['MemoryFade'] = df['Configuration'].apply(
            lambda x: extract_parameter(x, 'memory-fade')
        )
        
        print(f"Successfully loaded data with {len(df)} rows.")
        return df
    
    except Exception as e:
        print(f"Error loading data: {e}")
        return None

def extract_parameter(config_str, param_name, is_bool=False):
    """
    Extract a parameter value from the configuration string
    """
    if not isinstance(config_str, str):
        return None
    
    pattern = rf"{param_name}=([^_]+)"
    match = re.search(pattern, config_str)
    
    if match:
        value = match.group(1)
        if is_bool:
            return value.lower() == 'true'
        try:
            return float(value)
        except ValueError:
            return value
    return None

def summarize_experiment(df):
    """
    Generate overall summary statistics for the experiment
    """
    print("\n=== OVERALL EXPERIMENT SUMMARY ===")
    print(f"Total configurations: {df['Configuration'].nunique()}")
    print(f"Total runs: {len(df)}")
    
    # Overall statistics for key metrics
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage', 'SearchingPercentage',
        'OnTheFlyJobs', 'MemoryJobs', 'JobTypeRatio',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    summary = df[key_metrics].describe()
    print("\nOverall metrics summary:")
    print(summary)
    
    return summary

def analyze_by_configuration(df):
    """
    Group results by configuration and compute averages and std deviations
    """
    print("\n=== ANALYSIS BY CONFIGURATION ===")
    
    # Group by Configuration and compute mean, std for key metrics
    config_groups = df.groupby('Configuration')
    
    # Key metrics to analyze
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage', 'OnTheFlyJobs', 'MemoryJobs',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    # Calculate mean and std for each configuration
    config_summary = config_groups[key_metrics].agg(['mean', 'std'])
    
    # Display the results
    pd.set_option('display.max_columns', None)
    #pd.set_option('display.width', 500)
    print(config_summary)
    
    return config_summary

def compare_autonomy_levels(df):
    """
    Compare metrics across different autonomy levels
    """
    print("\n=== COMPARISON BY AUTONOMY LEVEL ===")
    
    # Check if AutonomyLevel column exists and has values
    if 'AutonomyLevel' not in df.columns or df['AutonomyLevel'].isna().all():
        print("No autonomy level data available for comparison")
        return None
    
    # Group by AutonomyLevel and compute statistics
    autonomy_groups = df.groupby('AutonomyLevel')
    
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage', 'SearchingPercentage',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    autonomy_summary = autonomy_groups[key_metrics].agg(['mean', 'std']).round(2)
    print(autonomy_summary)
    
    return autonomy_summary

def compare_cooperativeness_levels(df):
    """
    Compare metrics across different cooperativeness levels
    """
    print("\n=== COMPARISON BY COOPERATIVENESS LEVEL ===")
    
    # Check if CooperativenessLevel column exists and has values
    if 'CooperativenessLevel' not in df.columns or df['CooperativenessLevel'].isna().all():
        print("No cooperativeness level data available for comparison")
        return None
    
    # Group by CooperativenessLevel and compute statistics
    coop_groups = df.groupby('CooperativenessLevel')
    
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage', 'SearchingPercentage',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    coop_summary = coop_groups[key_metrics].agg(['mean', 'std']).round(2)
    print(coop_summary)
    
    return coop_summary

def analyze_memory_effects(df):
    """
    Analyze the effects of memory features (use-memory and memory-fade)
    """
    print("\n=== MEMORY EFFECTS ANALYSIS ===")
    
    # Check if memory-related columns exist
    if 'UseMemory' not in df.columns or df['UseMemory'].isna().all():
        print("No memory data available for analysis")
        # Return an empty dictionary instead of None
        return {"memory_summary": None, "fade_summary": None}
    
    # Compare metrics based on whether memory is used
    memory_groups = df.groupby('UseMemory')
    
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'OnTheFlyJobs', 'MemoryJobs',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    memory_summary = memory_groups[key_metrics].agg(['mean', 'std']).round(2)
    print("\nEffect of using memory:")
    print(memory_summary)
    
    # If memory fade data exists, analyze its effects
    fade_summary = None
    if 'MemoryFade' in df.columns and not df['MemoryFade'].isna().all():
        # Filter to only experiments with memory enabled
        memory_enabled_df = df[df['UseMemory'] == True]
        
        if len(memory_enabled_df) > 0:
            # Group by memory fade values
            fade_groups = memory_enabled_df.groupby('MemoryFade')
            fade_summary = fade_groups[key_metrics].agg(['mean', 'std']).round(2)
            
            print("\nEffect of different memory fade rates:")
            print(fade_summary)
    
    return {"memory_summary": memory_summary, "fade_summary": fade_summary}

def analyze_workload_balance(df):
    """
    Analyze how evenly work is distributed among couriers
    """
    print("\n=== WORKLOAD BALANCE ANALYSIS ===")
    
    # Measure of workload balance: DeliveriesPerCourierSD
    # Lower SD indicates more balanced workload distribution
    
    # Group by key experimental parameters
    balance_by_autonomy = df.groupby('AutonomyLevel')['DeliveriesPerCourierSD'].agg(['mean', 'min', 'max']).round(2)
    print("\nWorkload balance by autonomy level (lower SD = more balanced):")
    print(balance_by_autonomy)
    
    balance_by_coop = None
    if 'CooperativenessLevel' in df.columns and not df['CooperativenessLevel'].isna().all():
        balance_by_coop = df.groupby('CooperativenessLevel')['DeliveriesPerCourierSD'].agg(['mean', 'min', 'max']).round(2)
        print("\nWorkload balance by cooperativeness level (lower SD = more balanced):")
        print(balance_by_coop)
    
    # Calculate efficiency vs. balance tradeoff
    df['EfficiencyToBalanceRatio'] = df['TotalDeliveries'] / (df['DeliveriesPerCourierSD'] + 0.1)  # Add 0.1 to avoid division by zero
    
    efficiency_balance = df.groupby(['AutonomyLevel', 'CooperativenessLevel'])['EfficiencyToBalanceRatio'].mean().round(2)
    print("\nEfficiency to balance ratio by configuration (higher is better):")
    print(efficiency_balance)
    
    return {
        'balance_by_autonomy': balance_by_autonomy,
        'balance_by_coop': balance_by_coop,
        'efficiency_balance': efficiency_balance
    }

def analyze_open_orders(df):
    """
    Analyze open orders metrics and time window distribution
    """
    print("\n=== OPEN ORDERS ANALYSIS ===")
    
    # Check if open orders columns exist
    open_orders_cols = ['AvgOpenOrders', 'MaxOpenOrders']
    time_window_cols = [
        'CreatedWindow1', 'CreatedWindow2', 'CreatedWindow3', 'CreatedWindow4',
        'CompletedWindow1', 'CompletedWindow2', 'CompletedWindow3', 'CompletedWindow4'
    ]
    
    if not all(col in df.columns for col in open_orders_cols):
        print("Open orders metrics not found in the data")
        return None
    
    # Basic statistics for open orders
    open_orders_stats = df[open_orders_cols].describe().round(2)
    print("\nOpen Orders Statistics:")
    print(open_orders_stats)
    
    # Analyze open orders by autonomy level
    if 'AutonomyLevel' in df.columns and not df['AutonomyLevel'].isna().all():
        open_orders_by_autonomy = df.groupby('AutonomyLevel')[open_orders_cols].mean().round(2)
        print("\nOpen Orders by Autonomy Level:")
        print(open_orders_by_autonomy)
    
    # Analyze open orders by cooperativeness level
    if 'CooperativenessLevel' in df.columns and not df['CooperativenessLevel'].isna().all():
        open_orders_by_coop = df.groupby('CooperativenessLevel')[open_orders_cols].mean().round(2)
        print("\nOpen Orders by Cooperativeness Level:")
        print(open_orders_by_coop)
    
    # Analyze time window distribution if available
    if all(col in df.columns for col in time_window_cols):
        # Calculate totals and percentages for each time window
        window_totals = {
            'Created': df[['CreatedWindow1', 'CreatedWindow2', 'CreatedWindow3', 'CreatedWindow4']].sum().tolist(),
            'Completed': df[['CompletedWindow1', 'CompletedWindow2', 'CompletedWindow3', 'CompletedWindow4']].sum().tolist()
        }
        
        # Calculate percentages
        created_total = sum(window_totals['Created'])
        completed_total = sum(window_totals['Completed'])
        
        if created_total > 0:
            created_pct = [round(val*100/created_total, 2) for val in window_totals['Created']]
        else:
            created_pct = [0, 0, 0, 0]
            
        if completed_total > 0:
            completed_pct = [round(val*100/completed_total, 2) for val in window_totals['Completed']]
        else:
            completed_pct = [0, 0, 0, 0]
        
        # Create a summary table
        time_window_summary = pd.DataFrame({
            'Time Window': ['Window 1', 'Window 2', 'Window 3', 'Window 4'],
            'Created': window_totals['Created'],
            'Created %': created_pct,
            'Completed': window_totals['Completed'],
            'Completed %': completed_pct,
            'Completion Ratio': [c/o if o > 0 else 0 for c, o in zip(window_totals['Completed'], window_totals['Created'])]
        })
        
        print("\nTime Window Distribution:")
        print(time_window_summary)
        
        # Calculate completion efficiency by time window
        time_window_efficiency = pd.DataFrame({
            'Time Window': ['Window 1', 'Window 2', 'Window 3', 'Window 4'],
            'Created': window_totals['Created'],
            'Completed': window_totals['Completed'],
            'Completion %': [round(c*100/o, 2) if o > 0 else 0 for c, o in zip(window_totals['Completed'], window_totals['Created'])]
        })
        
        print("\nCompletion Efficiency by Time Window:")
        print(time_window_efficiency)
    
    # Analyze open orders relation to other metrics
    open_orders_correlations = df[open_orders_cols + ['TotalDeliveries', 'AvgDeliveryTime', 'CourierUtilization']].corr().round(2)
    print("\nCorrelations with Open Orders:")
    print(open_orders_correlations)
    
    return {
        'open_orders_stats': open_orders_stats,
        'open_orders_by_autonomy': open_orders_by_autonomy if 'AutonomyLevel' in df.columns else None,
        'open_orders_by_coop': open_orders_by_coop if 'CooperativenessLevel' in df.columns else None,
        'time_window_summary': time_window_summary if all(col in df.columns for col in time_window_cols) else None,
        'time_window_efficiency': time_window_efficiency if all(col in df.columns for col in time_window_cols) else None,
        'open_orders_correlations': open_orders_correlations
    }

def plot_efficiency_balance_ratio(df, output_dir='./figures'):
    """
    Create a scatter plot showing the efficiency-to-balance ratio.
    X-axis: Autonomy Level
    Y-axis: Cooperativeness Level
    Size of points: Efficiency-to-Balance Ratio (scaled to 0-1)
    """
    print("\n=== GENERATING EFFICIENCY-BALANCE RATIO SCATTER PLOT ===")
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Check if required columns exist
    required_cols = ['AutonomyLevel', 'CooperativenessLevel', 'EfficiencyToBalanceRatio']
    if not all(col in df.columns for col in required_cols):
        print("Missing required columns for efficiency-balance ratio scatter plot")
        return
    
    # Filter out rows with missing values
    plot_df = df[required_cols].dropna()
    
    if len(plot_df) == 0:
        print("No valid data for efficiency-balance ratio scatter plot")
        return
    
    # Create the scatter plot
    plt.figure(figsize=(12, 10))
    
    # Get unique values to create a better visualization
    autonomy_levels = sorted(plot_df['AutonomyLevel'].unique())
    coop_levels = sorted(plot_df['CooperativenessLevel'].unique())
    
    # Calculate average ratio for each (autonomy, coop) combination
    summary_df = plot_df.groupby(['AutonomyLevel', 'CooperativenessLevel'])['EfficiencyToBalanceRatio'].mean().reset_index()
    
    # Scale the ratio to 0-1 range
    min_ratio = summary_df['EfficiencyToBalanceRatio'].min()
    max_ratio = summary_df['EfficiencyToBalanceRatio'].max()
    
    if min_ratio == max_ratio:  # Handle edge case where all values are the same
        summary_df['ScaledRatio'] = 0.5
    else:
        summary_df['ScaledRatio'] = (summary_df['EfficiencyToBalanceRatio'] - min_ratio) / (max_ratio - min_ratio)
    
    # Create a scatter plot with size proportional to scaled ratio
    scatter = plt.scatter(
        summary_df['AutonomyLevel'],
        summary_df['CooperativenessLevel'],
        s=summary_df['ScaledRatio'] * 500,  # Larger scale for better visibility of scaled values
        c=summary_df['ScaledRatio'],
        cmap='viridis',
        alpha=0.7,
        edgecolors='black',
        vmin=0,
        vmax=1  # Force colormap to use full 0-1 range
    )
    
    # Add colorbar
    cbar = plt.colorbar(scatter)
    cbar.set_label('Scaled Efficiency-to-Balance Ratio (0-1)', rotation=270, labelpad=20)
    
    # Add labels for each point showing both scaled and original values
    for i, row in summary_df.iterrows():
        plt.annotate(
            f"{row['ScaledRatio']:.2f}\n({row['EfficiencyToBalanceRatio']:.2f})",
            (row['AutonomyLevel'], row['CooperativenessLevel']),
            textcoords="offset points",
            xytext=(0, 5),
            ha='center'
        )
    
    # Set axis labels and title
    plt.xlabel('Autonomy Level')
    plt.ylabel('Cooperativeness Level')
    plt.title('Scaled Efficiency-to-Balance Ratio (0-1) by Autonomy and Cooperativeness Levels')
    
    # Set x and y ticks to only show the actual levels
    plt.xticks(autonomy_levels)
    plt.yticks(coop_levels)
    
    # Add grid for better readability
    plt.grid(True, linestyle='--', alpha=0.7)
    
    # Add a legend explaining the scaling
    plt.figtext(
        0.5, 0.01,
        f"Scaling: Original values from {min_ratio:.2f} to {max_ratio:.2f} scaled to 0-1 range.\nValues shown as: Scaled (Original)",
        ha="center", fontsize=10, bbox={"facecolor":"lightgray", "alpha":0.5, "pad":5}
    )
    
    # Save the figure
    plt.tight_layout()
    plt.savefig(f"{output_dir}/efficiency_balance_ratio_scaled_scatter.png")
    print(f"Saved: efficiency_balance_ratio_scaled_scatter.png")
    plt.close()

def plot_efficiency_balance_heatmap(df, output_dir='./figures'):
    """
    Create a heatmap showing the efficiency-to-balance ratio and related metrics 
    across autonomy and cooperativeness levels. Shows only non-zero values, with 
    larger font and rounded integers.
    """
    print("\n=== GENERATING UPDATED EFFICIENCY-BALANCE RATIO HEATMAP ===")
    
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    required_cols = ['AutonomyLevel', 'CooperativenessLevel', 'EfficiencyToBalanceRatio',
                     'TotalDeliveries', 'DeliveriesPerCourierSD']
    if not all(col in df.columns for col in required_cols):
        print("Missing required columns for enhanced heatmap")
        return
    
    # Precompute values
    df['EfficiencyToBalanceRatio'] = df['TotalDeliveries'] / (df['DeliveriesPerCourierSD'] + 0.1)
    grouped = df.groupby(['AutonomyLevel', 'CooperativenessLevel']).agg({
        'EfficiencyToBalanceRatio': 'mean',
        'TotalDeliveries': 'mean',
        'DeliveriesPerCourierSD': 'mean'
    }).reset_index()
    
    # Scale the efficiency-to-balance ratio between 0–1
    min_val = grouped['EfficiencyToBalanceRatio'].min()
    max_val = grouped['EfficiencyToBalanceRatio'].max()
    grouped['ScaledEfficiency'] = (
        (grouped['EfficiencyToBalanceRatio'] - min_val) /
        (max_val - min_val) if max_val > min_val else 0.5
    )
    
    autonomy_levels = sorted(df['AutonomyLevel'].dropna().unique())
    coop_levels = sorted(df['CooperativenessLevel'].dropna().unique())

    heatmap_data = np.full((len(coop_levels), len(autonomy_levels)), np.nan)
    annotations = [['' for _ in autonomy_levels] for _ in coop_levels]

    for _, row in grouped.iterrows():
        i = coop_levels.index(row['CooperativenessLevel'])
        j = autonomy_levels.index(row['AutonomyLevel'])
        
        value = row['EfficiencyToBalanceRatio']
        if value > 0:
            heatmap_data[i, j] = value
            annotations[i][j] = (
                f"{int(round(row['TotalDeliveries']))}\n"
                f"{int(round(row['DeliveriesPerCourierSD']))}\n"
                f"{int(round(row['EfficiencyToBalanceRatio']))}\n"
                f"({row['ScaledEfficiency']:.2f})"
            )

    plt.figure(figsize=(12, 10))
    ax = sns.heatmap(
        heatmap_data,
        annot=annotations,
        fmt='',
        cmap='viridis',
        cbar_kws={'label': 'Efficiency-to-Balance Ratio'},
        linewidths=0.5,
        linecolor='gray',
        xticklabels=autonomy_levels,
        yticklabels=coop_levels,
        square=True,
        annot_kws={"fontsize": 13, "weight": "bold"}
    )

    ax.set_xlabel('Autonomy Level', fontsize=14)
    ax.set_ylabel('Cooperativeness Level', fontsize=14)
    ax.set_title('Efficiency-to-Balance Ratio Heatmap\n'
                 'Values: Total Deliveries | SD per Courier | Ratio | (Scaled Ratio)', fontsize=16)

    plt.xticks(fontsize=12)
    plt.yticks(fontsize=12)
    plt.tight_layout()
    plt.savefig(f"{output_dir}/enhanced_efficiency_balance_heatmap.png")
    print(f"Saved: enhanced_efficiency_balance_heatmap.png")
    plt.close()
def plot_open_orders_visualizations(df, output_dir='./figures'):
    """
    Generate visualizations specifically for open orders metrics
    """
    print("\n=== GENERATING OPEN ORDERS VISUALIZATIONS ===")
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Check if required columns exist
    required_cols = ['AvgOpenOrders', 'MaxOpenOrders']
    if not all(col in df.columns for col in required_cols):
        print("Missing required columns for open orders visualizations")
        return
    
    # Set up the visualization style
    sns.set(style="whitegrid")
    plt.rcParams.update({'font.size': 12})
    
    # 1. Open Orders by Autonomy Level
    if 'AutonomyLevel' in df.columns and not df['AutonomyLevel'].isna().all():
        plt.figure(figsize=(10, 6))
        
        # Calculate averages by autonomy level
        avg_open_orders = df.groupby('AutonomyLevel')['AvgOpenOrders'].mean()
        max_open_orders = df.groupby('AutonomyLevel')['MaxOpenOrders'].mean()
        
        # Create a grouped bar chart
        x = np.arange(len(avg_open_orders.index))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(12, 7))
        rects1 = ax.bar(x - width/2, avg_open_orders.values, width, label='Average Open Orders')
        rects2 = ax.bar(x + width/2, max_open_orders.values, width, label='Maximum Open Orders')
        
        # Add labels, title and legend
        ax.set_xlabel('Autonomy Level')
        ax.set_ylabel('Number of Orders')
        ax.set_title('Open Orders by Autonomy Level')
        ax.set_xticks(x)
        ax.set_xticklabels(avg_open_orders.index)
        ax.legend()
        
        # Add value labels on top of bars
        def add_labels(rects):
            for rect in rects:
                height = rect.get_height()
                ax.annotate(f'{height:.1f}',
                            xy=(rect.get_x() + rect.get_width() / 2, height),
                            xytext=(0, 3),
                            textcoords="offset points",
                            ha='center', va='bottom')
        
        add_labels(rects1)
        add_labels(rects2)
        
        fig.tight_layout()
        plt.savefig(f"{output_dir}/open_orders_by_autonomy.png")
        print(f"Saved: open_orders_by_autonomy.png")
        plt.close()
    
    # 2. Open Orders by Cooperativeness Level
    if 'CooperativenessLevel' in df.columns and not df['CooperativenessLevel'].isna().all():
        # Calculate averages by cooperativeness level
        avg_open_orders = df.groupby('CooperativenessLevel')['AvgOpenOrders'].mean()
        max_open_orders = df.groupby('CooperativenessLevel')['MaxOpenOrders'].mean()
        
        # Create a grouped bar chart
        x = np.arange(len(avg_open_orders.index))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(12, 7))
        rects1 = ax.bar(x - width/2, avg_open_orders.values, width, label='Average Open Orders')
        rects2 = ax.bar(x + width/2, max_open_orders.values, width, label='Maximum Open Orders')
        
        # Add labels, title and legend
        ax.set_xlabel('Cooperativeness Level')
        ax.set_ylabel('Number of Orders')
        ax.set_title('Open Orders by Cooperativeness Level')
        ax.set_xticks(x)
        ax.set_xticklabels(avg_open_orders.index)
        ax.legend()
        
        # Add value labels on top of bars
        add_labels(rects1)
        add_labels(rects2)
        
        fig.tight_layout()
        plt.savefig(f"{output_dir}/open_orders_by_coop.png")
        print(f"Saved: open_orders_by_coop.png")
        plt.close()
    
    # 3. Time window analysis if applicable
    time_window_cols = [
        'CreatedWindow1', 'CreatedWindow2', 'CreatedWindow3', 'CreatedWindow4',
        'CompletedWindow1', 'CompletedWindow2', 'CompletedWindow3', 'CompletedWindow4'
    ]
    
    if all(col in df.columns for col in time_window_cols):
        # Create a plot showing order creation and completion by time window
        created_cols = [col for col in time_window_cols if 'Created' in col]
        completed_cols = [col for col in time_window_cols if 'Completed' in col]
        
        # Calculate totals for each time window
        created_values = df[created_cols].sum()
        completed_values = df[completed_cols].sum()
        
        # Prepare data for plotting
        time_windows = ['Window 1', 'Window 2', 'Window 3', 'Window 4']
        created_data = created_values.values
        completed_data = completed_values.values
        
        # Create a grouped bar chart
        x = np.arange(len(time_windows))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(12, 7))
        rects1 = ax.bar(x - width/2, created_data, width, label='Created Orders')
        rects2 = ax.bar(x + width/2, completed_data, width, label='Completed Orders')
        
        # Add labels, title and legend
        ax.set_xlabel('Time Window')
        ax.set_ylabel('Number of Orders')
        ax.set_title('Orders Created and Completed by Time Window')
        ax.set_xticks(x)
        ax.set_xticklabels(time_windows)
        ax.legend()
        
        # Add value labels on top of bars
        add_labels(rects1)
        add_labels(rects2)
        
        fig.tight_layout()
        plt.savefig(f"{output_dir}/orders_by_time_window.png")
        print(f"Saved: orders_by_time_window.png")
        plt.close()
        
        # Create a completion ratio plot
        completion_ratio = []
        for i in range(4):
            if created_data[i] > 0:
                completion_ratio.append(completed_data[i] / created_data[i] * 100)
            else:
                completion_ratio.append(0)
        
        plt.figure(figsize=(12, 7))
        bars = plt.bar(time_windows, completion_ratio, color='skyblue')
        
        # Add data labels
        for bar in bars:
            height = bar.get_height()
            plt.text(bar.get_x() + bar.get_width()/2., height + 1,
                    f'{height:.1f}%', ha='center', va='bottom')
        
        plt.xlabel('Time Window')
        plt.ylabel('Completion Percentage')
        plt.title('Order Completion Ratio by Time Window')
        plt.ylim(0, 110)  # Leave room for the percentage labels
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/completion_ratio_by_time_window.png")
        print(f"Saved: completion_ratio_by_time_window.png")
        plt.close()
    
    # 4. Correlation between open orders and other metrics
    correlation_metrics = ['AvgOpenOrders', 'MaxOpenOrders', 'TotalDeliveries', 
                         'AvgDeliveryTime', 'CourierUtilization']
    
    if all(col in df.columns for col in correlation_metrics):
        # Create correlation heatmap
        plt.figure(figsize=(10, 8))
        corr = df[correlation_metrics].corr()
        mask = np.triu(np.ones_like(corr, dtype=bool))
        sns.heatmap(corr, mask=mask, annot=True, cmap='coolwarm', vmin=-1, vmax=1, 
                    fmt='.2f', linewidths=0.5)
        plt.title('Correlation Between Open Orders and Other Metrics')
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/open_orders_correlation.png")
        print(f"Saved: open_orders_correlation.png")
        plt.close()
        
    # 5. Scatter plot of open orders vs total deliveries
    if 'AvgOpenOrders' in df.columns and 'TotalDeliveries' in df.columns:
        plt.figure(figsize=(10, 6))
        sns.scatterplot(
            data=df,
            x='AvgOpenOrders',
            y='TotalDeliveries',
            hue='AutonomyLevel' if 'AutonomyLevel' in df.columns else None,
            size='CooperativenessLevel' if 'CooperativenessLevel' in df.columns else None,
            sizes=(50, 200),
            alpha=0.7
        )
        plt.title('Relationship Between Open Orders and Total Deliveries')
        plt.xlabel('Average Open Orders')
        plt.ylabel('Total Deliveries')
        
        # Add regression line
        sns.regplot(
            data=df,
            x='AvgOpenOrders',
            y='TotalDeliveries',
            scatter=False,
            line_kws={"color": "red", "alpha": 0.7, "lw": 2}
        )
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/open_orders_vs_deliveries.png")
        print(f"Saved: open_orders_vs_deliveries.png")
        plt.close()


def generate_visualizations(df, output_dir='./figures'):
    """
    Generate and save visualizations of the experimental results
    """
    print("\n=== GENERATING VISUALIZATIONS ===")
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Set up the visualization style
    sns.set(style="whitegrid")
    plt.rcParams.update({'font.size': 12})
    
    # 1. Compare TotalDeliveries across autonomy levels
    if 'AutonomyLevel' in df.columns and not df['AutonomyLevel'].isna().all():
        plt.figure(figsize=(10, 6))
        sns.barplot(x='AutonomyLevel', y='TotalDeliveries', data=df)
        plt.title('Total Deliveries by Autonomy Level')
        plt.xlabel('Autonomy Level')
        plt.ylabel('Total Deliveries')
        plt.savefig(f"{output_dir}/deliveries_by_autonomy.png")
        print(f"Saved: deliveries_by_autonomy.png")
        
    # 2. Compare efficiency metrics across configurations
    if len(df['Configuration'].unique()) <= 10:  # Only if we have a reasonable number of configurations
        plt.figure(figsize=(12, 8))
        metrics_to_plot = ['TotalDeliveries', 'AvgDeliveryTime', 'CourierUtilization']
        
        for i, metric in enumerate(metrics_to_plot):
            plt.subplot(len(metrics_to_plot), 1, i+1)
            sns.barplot(x='Configuration', y=metric, data=df)
            plt.title(f'{metric} by Configuration')
            plt.xticks(rotation=45, ha='right')
            plt.tight_layout()
        
        plt.savefig(f"{output_dir}/metrics_by_config.png")
        print(f"Saved: metrics_by_config.png")
    
    # 3. Workload balance visualization
    plt.figure(figsize=(10, 6))
    ax = sns.scatterplot(
        x='TotalDeliveries', 
        y='DeliveriesPerCourierSD', 
        hue='AutonomyLevel',
        size='CooperativenessLevel', 
        sizes=(50, 200),
        data=df
    )
    plt.title('Efficiency vs. Workload Balance')
    plt.xlabel('Total Deliveries (Efficiency)')
    plt.ylabel('Deliveries Per Courier SD (Balance)')
    plt.legend(title='Autonomy Level', bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig(f"{output_dir}/efficiency_vs_balance.png")
    print(f"Saved: efficiency_vs_balance.png")
    
    plot_efficiency_balance_ratio(df, output_dir)
    plot_efficiency_balance_heatmap(df, output_dir)
    plot_open_orders_visualizations(df, output_dir)

    # 4. Job types analysis
    plt.figure(figsize=(10, 6))
    job_types_df = df.groupby('Configuration')[['OnTheFlyJobs', 'MemoryJobs']].mean().reset_index()
    job_types_df = job_types_df.melt(
        id_vars=['Configuration'],
        value_vars=['OnTheFlyJobs', 'MemoryJobs'],
        var_name='Job Type',
        value_name='Count'
    )
    
    if len(job_types_df) > 0:
        sns.barplot(x='Configuration', y='Count', hue='Job Type', data=job_types_df)
        plt.title('Job Types by Configuration')
        plt.xticks(rotation=45, ha='right')
        plt.legend(title='Job Type')
        plt.tight_layout()
        plt.savefig(f"{output_dir}/job_types_by_config.png")
        print(f"Saved: job_types_by_config.png")
    
    print(f"All visualizations saved to {output_dir}")

def save_results_to_excel(results_dict, file_path):
    """
    Save all analysis results to an Excel file with multiple sheets
    """
    print("\n=== SAVING RESULTS TO EXCEL ===")
    
    # Create a timestamp for the output file
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    output_file = f"{file_path}_analysis_{timestamp}.xlsx"
    
    # Create an Excel writer
    with pd.ExcelWriter(output_file, engine='openpyxl') as writer:
        # Save the raw data
        if 'raw_data' in results_dict and results_dict['raw_data'] is not None:
            results_dict['raw_data'].to_excel(writer, sheet_name='Raw Data', index=False)
        
        # Save overall summary
        if 'overall_summary' in results_dict and results_dict['overall_summary'] is not None:
            results_dict['overall_summary'].to_excel(writer, sheet_name='Overall Summary')
        
        # Save configuration analysis
        if 'config_summary' in results_dict and results_dict['config_summary'] is not None:
            results_dict['config_summary'].to_excel(writer, sheet_name='Analysis by Configuration')
        
        # Save autonomy level comparison
        if 'autonomy_summary' in results_dict and results_dict['autonomy_summary'] is not None:
            if not results_dict['autonomy_summary'].empty:  # Check if DataFrame is not empty
                results_dict['autonomy_summary'].to_excel(writer, sheet_name='Autonomy Level Analysis')
        
        # Save cooperativeness level comparison
        if 'coop_summary' in results_dict and results_dict['coop_summary'] is not None:
            if not results_dict['coop_summary'].empty:  # Check if DataFrame is not empty
                results_dict['coop_summary'].to_excel(writer, sheet_name='Cooperativeness Analysis')
        
        # Save memory effects analysis
        if 'memory_effects' in results_dict and results_dict['memory_effects'] is not None:
            memory_data = results_dict['memory_effects']
            
            if 'memory_summary' in memory_data and memory_data['memory_summary'] is not None:
                memory_data['memory_summary'].to_excel(writer, sheet_name='Memory Usage Effects')
            
            if 'fade_summary' in memory_data and memory_data['fade_summary'] is not None:
                memory_data['fade_summary'].to_excel(writer, sheet_name='Memory Fade Effects')
        
        # Save open orders analysis
        if 'open_orders_analysis' in results_dict and results_dict['open_orders_analysis'] is not None:
            open_orders_data = results_dict['open_orders_analysis']
            
            # Create a new sheet for open orders analysis
            sheet_name = 'Open Orders Analysis'
            
            # Write each part to the sheet
            row_position = 0
            
            if 'open_orders_stats' in open_orders_data and open_orders_data['open_orders_stats'] is not None:
                # Write a header
                worksheet = writer.sheets[sheet_name] if sheet_name in writer.sheets else None
                if worksheet is None:
                    # If sheet doesn't exist yet, pandas will create it
                    pass
                else:
                    worksheet.cell(row=row_position+1, column=1, value="Open Orders Basic Statistics")
                
                open_orders_data['open_orders_stats'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(open_orders_data['open_orders_stats']) + 3  # Add some spacing
            
            if 'open_orders_by_autonomy' in open_orders_data and open_orders_data['open_orders_by_autonomy'] is not None:
                # Write a header
                worksheet = writer.sheets.get(sheet_name)
                if worksheet:
                    worksheet.cell(row=row_position+1, column=1, value="Open Orders by Autonomy Level")
                
                open_orders_data['open_orders_by_autonomy'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(open_orders_data['open_orders_by_autonomy']) + 3
            
            if 'open_orders_by_coop' in open_orders_data and open_orders_data['open_orders_by_coop'] is not None:
                # Write a header
                worksheet = writer.sheets.get(sheet_name)
                if worksheet:
                    worksheet.cell(row=row_position+1, column=1, value="Open Orders by Cooperativeness Level")
                
                open_orders_data['open_orders_by_coop'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(open_orders_data['open_orders_by_coop']) + 3
            
            if 'time_window_summary' in open_orders_data and open_orders_data['time_window_summary'] is not None:
                # Write a header
                worksheet = writer.sheets.get(sheet_name)
                if worksheet:
                    worksheet.cell(row=row_position+1, column=1, value="Time Window Distribution")
                
                open_orders_data['time_window_summary'].to_excel(writer, sheet_name=sheet_name, startrow=row_position, index=False)
                row_position += len(open_orders_data['time_window_summary']) + 3
            
            if 'time_window_efficiency' in open_orders_data and open_orders_data['time_window_efficiency'] is not None:
                # Write a header
                worksheet = writer.sheets.get(sheet_name)
                if worksheet:
                    worksheet.cell(row=row_position+1, column=1, value="Completion Efficiency by Time Window")
                
                open_orders_data['time_window_efficiency'].to_excel(writer, sheet_name=sheet_name, startrow=row_position, index=False)
                row_position += len(open_orders_data['time_window_efficiency']) + 3
            
            if 'open_orders_correlations' in open_orders_data and open_orders_data['open_orders_correlations'] is not None:
                # Write a header
                worksheet = writer.sheets.get(sheet_name)
                if worksheet:
                    worksheet.cell(row=row_position+1, column=1, value="Correlations with Open Orders")
                
                open_orders_data['open_orders_correlations'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(open_orders_data['open_orders_correlations']) + 3
        
        # Save workload balance analysis
        if 'workload_balance' in results_dict and results_dict['workload_balance'] is not None:
            balance_data = results_dict['workload_balance']
            
            # Create a new sheet for workload balance
            sheet_name = 'Workload Balance'
            
            # Write each part to the sheet
            row_position = 0
            
            if 'balance_by_autonomy' in balance_data and balance_data['balance_by_autonomy'] is not None:
                balance_data['balance_by_autonomy'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(balance_data['balance_by_autonomy']) + 3  # Add some spacing
            
            if 'balance_by_coop' in balance_data and balance_data['balance_by_coop'] is not None:
                balance_data['balance_by_coop'].to_excel(writer, sheet_name=sheet_name, startrow=row_position)
                row_position += len(balance_data['balance_by_coop']) + 3
            
            if 'efficiency_balance' in balance_data and balance_data['efficiency_balance'] is not None:
                # Convert Series to DataFrame for Excel output
                efficiency_df = balance_data['efficiency_balance'].reset_index()
                efficiency_df.columns = ['Autonomy Level', 'Cooperativeness Level', 'Efficiency to Balance Ratio']
                efficiency_df.to_excel(writer, sheet_name=sheet_name, startrow=row_position, index=False)
        
        # Save statistical comparison matrices
        if 'stat_comparisons' in results_dict and results_dict['stat_comparisons'] is not None:
            stat_comparisons = results_dict['stat_comparisons']
            
            # Create a formatted worksheet for each metric comparison
            for metric, p_value_matrix in stat_comparisons.items():
                sheet_name = f'Stat Comparison - {metric}'
                
                # Write the raw p-values
                p_value_matrix.to_excel(writer, sheet_name=sheet_name)
                
                # Get the workbook and worksheet objects
                workbook = writer.book
                worksheet = writer.sheets[sheet_name]
                
                # Add a color-coded version on the same sheet with some separation
                row_offset = len(p_value_matrix) + 3
                
                # Add a header for the color-coded section
                worksheet.cell(row=row_offset, column=1, value="Color-coded Significance (p < 0.05 highlighted)")
                
                # Create a copy of the matrix for coloring
                color_matrix = p_value_matrix.copy()
                
                # Write the color-coded matrix
                color_matrix.to_excel(writer, sheet_name=sheet_name, startrow=row_offset + 1)
                
                # The sheet will be added with all values. We'll need to format it later
                # in Excel with conditional formatting. We can add a note about this.
                note_row = row_offset + len(color_matrix) + 3
                worksheet.cell(row=note_row, column=1, value="Note: Values < 0.05 indicate statistically significant differences (p < 0.05)")

        # Save parameter effects analysis
        if 'parameter_effects' in results_dict and results_dict['parameter_effects'] is not None:
            param_effects = results_dict['parameter_effects']
            
            # Create a new sheet
            sheet_name = 'Parameter Effects'
            
            # Convert the nested dictionary to a DataFrame for easier display
            effect_rows = []
            
            for param_name, metrics in param_effects.items():
                for metric_name, details in metrics.items():
                    effect_rows.append({
                        'Parameter': param_name,
                        'Metric': metric_name,
                        'P-Value': details['p_value'],
                        'Test': details['test_type'],
                        'Significant': 'Yes' if details['significant'] else 'No'
                    })
            
            # Create DataFrame and write to Excel
            if effect_rows:
                effects_df = pd.DataFrame(effect_rows)
                effects_df.to_excel(writer, sheet_name=sheet_name, index=False)
    
    print(f"All results saved to: {output_file}")
    return output_file
    
def compare_configurations_statistically(df):
    """
    Perform statistical comparison between different configurations and create 
    a matrix showing p-values for significant differences
    """
    print("\n=== STATISTICAL COMPARISON BETWEEN CONFIGURATIONS ===")
    
    # Key metrics to compare statistically
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage', 'OnTheFlyJobs',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    # Get all unique configurations
    configurations = df['Configuration'].unique()
    
    # Only proceed if we have multiple configurations to compare
    if len(configurations) <= 1:
        print("Not enough configurations to compare.")
        return None
    
    # Create result dictionaries for each metric
    stat_comparisons = {}
    
    for metric in key_metrics:
        # Skip metrics that don't exist in the dataframe
        if metric not in df.columns:
            continue
            
        print(f"\nComparing {metric} across configurations...")
        
        # Create comparison matrix
        p_value_matrix = pd.DataFrame(
            index=configurations,
            columns=configurations
        )
        
        # Perform pairwise t-tests
        for config1, config2 in itertools.combinations(configurations, 2):
            # Get data for each configuration
            data1 = df[df['Configuration'] == config1][metric].dropna()
            data2 = df[df['Configuration'] == config2][metric].dropna()
            
            # Only perform test if we have enough data
            if len(data1) >= 2 and len(data2) >= 2:
                # Perform Welch's t-test (does not assume equal variances)
                t_stat, p_value = stats.ttest_ind(data1, data2, equal_var=False)
                
                # Store p-value in the matrix
                p_value_matrix.loc[config1, config2] = p_value
                p_value_matrix.loc[config2, config1] = p_value
            else:
                p_value_matrix.loc[config1, config2] = np.nan
                p_value_matrix.loc[config2, config1] = np.nan
        
        # Fill diagonal with 1.0 (no difference with itself)
        for config in configurations:
            p_value_matrix.loc[config, config] = 1.0
            
        # Store the comparison matrix for this metric
        stat_comparisons[metric] = p_value_matrix
        
        # Display some of the significant findings
        p_value_matrix_filtered = p_value_matrix.copy()
        p_value_matrix_filtered = p_value_matrix_filtered.applymap(
            lambda x: x if pd.notnull(x) and x < 0.05 else np.nan
        )
        
        # Show significant differences
        if p_value_matrix_filtered.notna().any().any():
            print(f"  Significant differences found for {metric} (p < 0.05):")
            for config1, config2 in itertools.combinations(configurations, 2):
                p_val = p_value_matrix.loc[config1, config2]
                if pd.notnull(p_val) and p_val < 0.05:
                    # Get mean values to determine direction of difference
                    mean1 = df[df['Configuration'] == config1][metric].mean()
                    mean2 = df[df['Configuration'] == config2][metric].mean()
                    comp_symbol = ">" if mean1 > mean2 else "<"
                    
                    print(f"  - {config1} {comp_symbol} {config2} (p={p_val:.4f})")
        else:
            print(f"  No statistically significant differences found for {metric}")
        
    return stat_comparisons

def analyze_parameter_effects(df):
    """
    Analyze the statistical significance of individual parameters on key metrics
    """
    print("\n=== PARAMETER EFFECTS ANALYSIS ===")
    
    # Key metrics to analyze
    key_metrics = [
        'TotalDeliveries', 'AvgDeliveryTime', 'AvgEarnings', 
        'CourierUtilization', 'WaitingPercentage',
        # New open orders metrics
        'AvgOpenOrders', 'MaxOpenOrders'
    ]
    
    # Parameters to analyze
    parameters = [
        ('AutonomyLevel', 'Autonomy Level'),
        ('CooperativenessLevel', 'Cooperativeness Level'),
        ('UseMemory', 'Memory Usage')
    ]
    
    results = {}
    
    for param_col, param_name in parameters:
        # Check if parameter exists in data
        if param_col not in df.columns or df[param_col].isna().all():
            print(f"No {param_name} data available for analysis")
            continue
        
        print(f"\nAnalyzing {param_name} effect on metrics:")
        param_effects = {}
        
        for metric in key_metrics:
            # Skip metrics that don't exist in the dataframe
            if metric not in df.columns:
                continue
                
            # Prepare data for analysis
            metric_data = df[[param_col, metric]].dropna()
            
            # Check data type to determine appropriate test
            if metric_data[param_col].dtype == bool or len(metric_data[param_col].unique()) <= 2:
                # Boolean or binary parameter - use t-test
                groups = metric_data.groupby(param_col)[metric]
                group_values = [group for _, group in groups]
                
                if len(group_values) >= 2 and all(len(g) >= 2 for g in group_values):
                    # Perform t-test
                    t_stat, p_value = stats.ttest_ind(
                        group_values[0], 
                        group_values[1], 
                        equal_var=False
                    )
                    test_type = "t-test"
                else:
                    p_value = np.nan
                    test_type = "insufficient data"
            
            elif metric_data[param_col].dtype == 'object' or len(metric_data[param_col].unique()) <= 10:
                # Categorical parameter - use ANOVA
                groups = metric_data.groupby(param_col)[metric]
                group_values = [group for _, group in groups]
                
                if len(group_values) >= 2 and all(len(g) >= 2 for g in group_values):
                    # Perform one-way ANOVA
                    f_stat, p_value = stats.f_oneway(*group_values)
                    test_type = "ANOVA"
                else:
                    p_value = np.nan
                    test_type = "insufficient data"
            
            else:
                # Continuous parameter - use correlation
                correlation, p_value = stats.pearsonr(
                    metric_data[param_col], 
                    metric_data[metric]
                )
                test_type = f"correlation (r={correlation:.3f})"
            
            # Store and report results
            param_effects[metric] = {
                'p_value': p_value,
                'test_type': test_type,
                'significant': p_value < 0.05 if not np.isnan(p_value) else False
            }
            
            if not np.isnan(p_value) and p_value < 0.05:
                print(f"  {metric}: Significant effect (p={p_value:.4f}, {test_type})")
            else:
                p_val_str = f"{p_value:.4f}" if not np.isnan(p_value) else "N/A"
                print(f"  {metric}: No significant effect (p={p_val_str}, {test_type})")
        
        results[param_name] = param_effects
    
    return results

def main():
    """
    Main function to run the analysis
    """
    import os
    print(f"Current working directory: {os.getcwd()}")
    print("Files in this directory:")
    for file in os.listdir():
        print(f"  - {file}")
    
    # Get file path from command line or use default
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    else:
        file_path = "courier_experiment_results_09-46-47.647_am_18-Mar-2025.csv"
    
    # Check if file_path has .csv extension, if not, add it
    if not file_path.endswith('.csv'):
        csv_file_path = file_path + '.csv'
    else:
        csv_file_path = file_path
        file_path = file_path[:-4]  # Remove .csv for output naming
    
    # Load and parse the data
    df = load_and_parse_csv(csv_file_path)
    
    if df is None or len(df) == 0:
        print("No data to analyze. Exiting.")
        return
    
    # Dictionary to store all results
    results = {'raw_data': df}
    
    # Run the analyses
    results['overall_summary'] = summarize_experiment(df)
    results['config_summary'] = analyze_by_configuration(df)
    results['autonomy_summary'] = compare_autonomy_levels(df)
    results['coop_summary'] = compare_cooperativeness_levels(df)
    results['memory_effects'] = analyze_memory_effects(df)
    results['workload_balance'] = analyze_workload_balance(df)
    
    # Perform statistical comparisons between configurations
    results['stat_comparisons'] = compare_configurations_statistically(df)
    
    # Analyze statistical significance of parameters
    results['parameter_effects'] = analyze_parameter_effects(df)
    
    # Generate visualizations
    generate_visualizations(df)
    
    # Save results to Excel
    excel_file = save_results_to_excel(results, file_path)
    
    print("\nAnalysis completed successfully!")
    print(f"Excel report generated: {excel_file}")

if __name__ == "__main__":
    main()