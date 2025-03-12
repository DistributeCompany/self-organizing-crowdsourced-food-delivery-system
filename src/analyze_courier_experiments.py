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
            'MemoryJobs', 'JobTypeRatio', 'AvgJobsPerCourier', 'JobsPerCourierSD'
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
        'OnTheFlyJobs', 'MemoryJobs', 'JobTypeRatio'
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
        'CourierUtilization', 'WaitingPercentage', 'OnTheFlyJobs', 'MemoryJobs'
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
        'CourierUtilization', 'WaitingPercentage', 'SearchingPercentage'
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
        'CourierUtilization', 'WaitingPercentage', 'SearchingPercentage'
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
        'CourierUtilization', 'OnTheFlyJobs', 'MemoryJobs'
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
    Create a heatmap showing the efficiency-to-balance ratio across all combinations
    of autonomy levels (x-axis) and cooperativeness levels (y-axis).
    Y-axis is displayed from 0 (bottom) to 3 (top).
    """
    print("\n=== GENERATING EFFICIENCY-BALANCE RATIO HEATMAP ===")
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Check if required columns exist
    required_cols = ['AutonomyLevel', 'CooperativenessLevel', 'EfficiencyToBalanceRatio']
    if not all(col in df.columns for col in required_cols):
        print("Missing required columns for efficiency-balance ratio heatmap")
        return
    
    # Filter out rows with missing values
    plot_df = df[required_cols].dropna()
    
    if len(plot_df) == 0:
        print("No valid data for efficiency-balance ratio heatmap")
        return
    
    # Calculate average ratio for each (autonomy, coop) combination
    summary_df = plot_df.groupby(['AutonomyLevel', 'CooperativenessLevel'])['EfficiencyToBalanceRatio'].mean().reset_index()
    
    # Extract unique levels and sort them
    autonomy_levels = sorted(plot_df['AutonomyLevel'].unique())
    coop_levels = sorted(plot_df['CooperativenessLevel'].unique())
    
    # Create a 2D numpy array for the heatmap values
    heatmap_data = np.zeros((len(coop_levels), len(autonomy_levels)))
    
    # Fill the array with values from the grouped data
    for i, coop in enumerate(coop_levels):
        for j, auto in enumerate(autonomy_levels):
            # Filter to get the value for this combination
            mask = (summary_df['AutonomyLevel'] == auto) & (summary_df['CooperativenessLevel'] == coop)
            if any(mask):
                heatmap_data[i, j] = summary_df.loc[mask, 'EfficiencyToBalanceRatio'].values[0]
    
    # Create the heatmap using imshow with origin='lower' to put (0,0) at bottom-left
    plt.figure(figsize=(12, 10))
    im = plt.imshow(heatmap_data, cmap='viridis', origin='lower', aspect='auto')
    
    # Add colorbar
    cbar = plt.colorbar(im)
    cbar.set_label('Efficiency-to-Balance Ratio', rotation=270, labelpad=20)
    
    # Set ticks and labels
    plt.xticks(range(len(autonomy_levels)), autonomy_levels)
    plt.yticks(range(len(coop_levels)), coop_levels)
    
    # Add text annotations for the values
    for i in range(len(coop_levels)):
        for j in range(len(autonomy_levels)):
            plt.text(j, i, f'{heatmap_data[i, j]:.2f}', 
                     ha='center', va='center', color='white', fontweight='bold')
    
    # Add labels and title
    plt.xlabel('Autonomy Level')
    plt.ylabel('Cooperativeness Level')
    plt.title('Efficiency-to-Balance Ratio Heatmap')
    
    # Add grid lines
    plt.grid(False)
    
    # Save the figure
    plt.tight_layout()
    plt.savefig(f"{output_dir}/efficiency_balance_ratio_heatmap.png")
    print(f"Saved: efficiency_balance_ratio_heatmap.png")
    plt.close()
    
    # Create a scaled version (0-1)
    plt.figure(figsize=(12, 10))
    
    # Find min and max values for scaling
    min_val = np.min(heatmap_data)
    max_val = np.max(heatmap_data)
    
    # Create scaled data
    if min_val == max_val:  # Handle edge case where all values are the same
        scaled_data = np.full_like(heatmap_data, 0.5)
    else:
        scaled_data = (heatmap_data - min_val) / (max_val - min_val)
    
    # Create the scaled heatmap
    im = plt.imshow(scaled_data, cmap='viridis', origin='lower', aspect='auto', vmin=0, vmax=1)
    
    # Add colorbar
    cbar = plt.colorbar(im)
    cbar.set_label('Scaled Efficiency-to-Balance Ratio (0-1)', rotation=270, labelpad=20)
    
    # Set ticks and labels
    plt.xticks(range(len(autonomy_levels)), autonomy_levels)
    plt.yticks(range(len(coop_levels)), coop_levels)
    
    # Add text annotations showing both scaled and original values
    for i in range(len(coop_levels)):
        for j in range(len(autonomy_levels)):
            plt.text(j, i, f'{scaled_data[i, j]:.2f}\n({heatmap_data[i, j]:.2f})', 
                     ha='center', va='center', color='white', fontweight='bold', fontsize=9)
    
    # Add labels and title
    plt.xlabel('Autonomy Level')
    plt.ylabel('Cooperativeness Level')
    plt.title('Scaled Efficiency-to-Balance Ratio Heatmap (0-1)')
    
    # Add a note about the scaling
    plt.figtext(
        0.5, 0.01,
        f"Scaling: Original values from {min_val:.2f} to {max_val:.2f} scaled to 0-1 range.\nValues shown as: Scaled (Original)",
        ha="center", fontsize=10, bbox={"facecolor":"lightgray", "alpha":0.5, "pad":5}
    )
    
    # Save the scaled figure
    plt.tight_layout()
    plt.savefig(f"{output_dir}/efficiency_balance_ratio_scaled_heatmap.png")
    print(f"Saved: efficiency_balance_ratio_scaled_heatmap.png")
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
        'CourierUtilization', 'WaitingPercentage', 'OnTheFlyJobs'
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
        'CourierUtilization', 'WaitingPercentage'
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
                print(f"  {metric}: No significant effect (p={p_value:.4f} if not np.isnan(p_value) else 'N/A'), {test_type})")
        
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
        file_path = "courier_experiment_results_10-25-43.973_am_11-Mar-2025.csv"
    
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