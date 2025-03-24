import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
import math
import os
import glob
from datetime import datetime

def merge_csv_files(input_files=None, output_file=None, add_source_column=True):
    """
    Merge multiple CSV files into a single CSV file.
    
    Parameters:
    -----------
    input_files : list or None
        List of input CSV file paths. If None, all CSV files in the current directory will be used.
    output_file : str or None
        Path for the output merged CSV file. If None, a default name with timestamp will be used.
    add_source_column : bool
        Whether to add a column indicating the source file for each row. Default is True.
    
    Returns:
    --------
    str
        Path to the created merged CSV file
    """
    # If no input files are specified, find all CSV files in the current directory
    if input_files is None:
        input_files = glob.glob("courier_experiment_results_*.csv")
    
    # Exclude the output file from input files if it exists
    if output_file and output_file in input_files:
        input_files.remove(output_file)
    
    # Check if there are any input files
    if not input_files:
        print("No CSV files found for merging")
        return None
    
    # Create default output filename if not provided
    if output_file is None:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f"merged_experiments_{timestamp}.csv"
    
    print(f"Merging {len(input_files)} CSV files:")
    for file in input_files:
        print(f"  - {file}")
    
    # Read and merge all CSV files
    all_data = []
    for file in input_files:
        try:
            # Read the CSV file
            df = pd.read_csv(file)
            
            # Add source file column if requested
            if add_source_column:
                df['SourceFile'] = os.path.basename(file)
            
            # Add to the list of dataframes
            all_data.append(df)
            print(f"  Successfully read {len(df)} rows from {file}")
        except Exception as e:
            print(f"  Error reading {file}: {str(e)}")
    
    # Merge all dataframes
    if not all_data:
        print("No data could be read from the input files")
        return None
    
    merged_df = pd.concat(all_data, ignore_index=True)
    print(f"Merged data has {len(merged_df)} total rows and {len(merged_df.columns)} columns")
    
    # Save the merged data
    merged_df.to_csv(output_file, index=False)
    print(f"Merged CSV saved to {output_file}")
    
    # Print summary of rows contributed by each source file
    if add_source_column:
        print("\nRows contributed by each file:")
        for file, count in merged_df['SourceFile'].value_counts().items():
            print(f"  {file}: {count} rows")
    
    return output_file, merged_df

def calculate_replications(data, variable, relative_precision=0.1, confidence=0.95):
    """
    Calculate the number of replications required to guarantee that the actual average
    is within a specified relative precision (±relative_precision) from the estimated average
    with the given confidence level.
    
    Parameters:
    -----------
    data : pandas.DataFrame
        The dataset containing the variable
    variable : str
        The name of the variable to analyze
    relative_precision : float, optional
        The desired relative precision as a proportion (default is 0.1, meaning ±10%)
    confidence : float, optional
        The confidence level (default is 0.95)
    
    Returns:
    --------
    dict
        A dictionary containing the results including required replications
        and confidence intervals for each configuration
    """
    results = {}
    
    # Check if 'Configuration' column exists
    if 'Configuration' not in data.columns:
        raise ValueError("Column 'Configuration' not found in the data")
    
    # Check if the variable column exists
    if variable not in data.columns:
        raise ValueError(f"Column '{variable}' not found in the data")
    
    configurations = data['Configuration'].unique()
    for config in configurations:
        config_data = data[data['Configuration'] == config]
        
        # Skip configurations with no data
        if len(config_data) == 0:
            continue
            
        # Ensure the variable column has numeric data
        values = pd.to_numeric(config_data[variable], errors='coerce').dropna().values
        
        # Skip if no valid numeric values
        if len(values) == 0:
            continue
        
        # Current sample size
        n = len(values)
        
        # Sample mean and standard deviation
        mean = np.mean(values)
        std = np.std(values, ddof=1)  # Using n-1 for sample std
        
        # Critical value for the t-distribution
        # Handle case where we only have 1 sample (n=1)
        if n <= 1:
            # Can't calculate t-critical for 0 degrees of freedom
            t_critical = float('nan')
        else:
            alpha = 1 - confidence
            t_critical = stats.t.ppf(1 - alpha/2, n-1)
        
        # Calculate absolute precision required based on the mean
        absolute_precision = relative_precision * abs(mean) if mean != 0 else relative_precision
        
        # Current half-width of CI
        if math.isnan(t_critical) or n <= 1:
            current_half_width = float('nan')
        else:
            current_half_width = t_critical * (std / math.sqrt(n))
        
        # Required sample size to achieve desired absolute precision
        # Handle case where std is zero or very close to zero
        if std < 1e-10:  # Using a small threshold instead of exactly zero
            required_n = 1  # If std is zero, we only need 1 sample (perfect precision)
        else:
            try:
                required_n = math.ceil((t_critical * std / absolute_precision) ** 2)
                # Check for NaN or infinity
                if math.isnan(required_n) or math.isinf(required_n):
                    required_n = float('inf')  # Set to infinity to indicate it's not calculable
            except:
                required_n = float('inf')  # Handle any other calculation errors
        
        # Calculate current confidence interval
        # Handle NaN or infinity in current_half_width
        if math.isnan(current_half_width) or math.isinf(current_half_width):
            ci_lower = float('nan')
            ci_upper = float('nan')
        else:
            ci_lower = mean - current_half_width
            ci_upper = mean + current_half_width
        
        # Store results
        results[config] = {
            'mean': mean,
            'std': std,
            'current_sample_size': n,
            'current_half_width': current_half_width,
            'current_ci': (ci_lower, ci_upper),
            'required_replications': required_n,
            'absolute_precision': absolute_precision,
            'precision_percentage': f"±{relative_precision:.1f}"
        }
    
    return results

def plot_required_replications(results, filename="required_replications.png"):
    """
    Create a bar plot of the required replications for each configuration.
    
    Parameters:
    -----------
    results : dict
        The dictionary of results from calculate_replications
    filename : str
        The filename to save the plot to
    
    Returns:
    --------
    matplotlib.figure.Figure
        The figure object
    """
    configs = []
    required_n = []
    current_n = []
    
    for config, result in results.items():
        configs.append(config)
        required_n.append(result['required_replications'])
        current_n.append(result['current_sample_size'])
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    x = np.arange(len(configs))
    width = 0.35
    
    ax.bar(x - width/2, current_n, width, label='Current Replications')
    ax.bar(x + width/2, required_n, width, label='Required Replications')
    
    ax.set_ylabel('Number of Replications')
    ax.set_title('Required Replications for Desired Confidence Interval Width')
    ax.set_xticks(x)
    ax.set_xticklabels(configs, rotation=45, ha='right')
    ax.legend()
    
    # Add value labels on bars
    for i, v in enumerate(current_n):
        ax.text(i - width/2, v + 0.1, str(v), ha='center')
    
    for i, v in enumerate(required_n):
        if not math.isinf(v):
            ax.text(i + width/2, v + 0.1, str(v), ha='center')
        else:
            ax.text(i + width/2, max(current_n) * 1.1, "∞", ha='center')
    
    fig.tight_layout()
    fig.savefig(filename)
    print(f"Plot saved as '{filename}'")
    return fig

def plot_confidence_intervals(results, variable, filename="confidence_intervals.png"):
    """
    Create a plot of the confidence intervals for each configuration.
    
    Parameters:
    -----------
    results : dict
        The dictionary of results from calculate_replications
    variable : str
        The name of the variable being analyzed
    filename : str
        The filename to save the plot to
    
    Returns:
    --------
    matplotlib.figure.Figure
        The figure object
    """
    configs = []
    means = []
    lower_bounds = []
    upper_bounds = []
    half_widths = []
    
    for config, result in results.items():
        # Skip configurations with NaN or infinite confidence intervals
        if (math.isnan(result['current_ci'][0]) or math.isnan(result['current_ci'][1]) or
            math.isinf(result['current_ci'][0]) or math.isinf(result['current_ci'][1])):
            continue
            
        configs.append(config)
        means.append(result['mean'])
        lower_bounds.append(result['current_ci'][0])
        upper_bounds.append(result['current_ci'][1])
        half_widths.append(result['current_half_width'])
    
    # Skip plotting if no valid configurations
    if not configs:
        print(f"No valid confidence intervals to plot for {variable}")
        return None
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    x = np.arange(len(configs))
    
    # Plot means and confidence intervals
    ax.errorbar(x, means, yerr=[
        np.array(means) - np.array(lower_bounds), 
        np.array(upper_bounds) - np.array(means)
    ], fmt='o', capsize=5, elinewidth=2, markersize=8)
    
    # Add horizontal lines for the precision bounds
    for i, config in enumerate(configs):
        precision = results[config]['absolute_precision']
        ax.plot([x[i]-0.2, x[i]+0.2], [means[i] + precision, means[i] + precision], 'r--')
        ax.plot([x[i]-0.2, x[i]+0.2], [means[i] - precision, means[i] - precision], 'r--')
    
    # Add a legend entry for precision bounds
    ax.plot([], [], 'r--', label=f'Precision Bounds ({results[configs[0]]["precision_percentage"]})')
    
    # Add labels for the half-widths
    for i, hw in enumerate(half_widths):
        # Position the text relative to the data range
        y_range = max(means) - min(means)
        y_pos = means[i] + hw + (y_range * 0.05)
        ax.text(x[i], y_pos, f'Half-width: {hw:.2f}', ha='center')
    
    ax.set_ylabel(variable)
    ax.set_title(f'Confidence Intervals for {variable}')
    ax.set_xticks(x)
    ax.set_xticklabels(configs, rotation=45, ha='right')
    ax.legend()
    
    fig.tight_layout()
    fig.savefig(filename)
    print(f"Plot saved as '{filename}'")
    return fig

def generate_report(results, variable):
    """
    Generate a text report summarizing the replication analysis.
    
    Parameters:
    -----------
    results : dict
        The dictionary of results from calculate_replications
    variable : str
        The name of the variable that was analyzed
    
    Returns:
    --------
    str
        A formatted text report
    """
    report = f"Replication Analysis for {variable}\n"
    report += "=" * 40 + "\n\n"
    
    for config, result in results.items():
        report += f"Configuration: {config}\n"
        report += "-" * 30 + "\n"
        report += f"Current sample size: {result['current_sample_size']}\n"
        report += f"Mean {variable}: {result['mean']:.2f}\n"
        report += f"Standard deviation: {result['std']:.2f}\n"
        
        if not math.isnan(result['current_half_width']) and not math.isinf(result['current_half_width']):
            report += f"Current half-width of CI: {result['current_half_width']:.2f}\n"
            report += f"Current CI: ({result['current_ci'][0]:.2f}, {result['current_ci'][1]:.2f})\n"
        else:
            report += "Current half-width of CI: Not calculable\n"
            report += "Current CI: Not calculable\n"
            
        report += f"Target precision: {result['precision_percentage']} ({result['absolute_precision']:.4f})\n"
        
        if not math.isinf(result['required_replications']):
            report += f"Required replications: {result['required_replications']}\n"
            
            if result['required_replications'] <= result['current_sample_size']:
                report += "Status: ✓ Current replications are sufficient\n"
            else:
                additional = result['required_replications'] - result['current_sample_size']
                report += f"Status: ✗ Need {additional} more replications\n"
        else:
            report += "Required replications: Cannot be determined\n"
            report += "Status: ? Unable to calculate required replications\n"
        
        report += "\n"
    
    return report

def main():
    """
    Main function to run the replication analysis on merged experiment data.
    """
    # Step 1: Merge all CSV files
    print("Step 1: Merging CSV files")
    output_file, merged_df = merge_csv_files()
    
    if merged_df is None:
        print("Error: Could not merge CSV files. Exiting.")
        return
    
    # Step 2: Calculate replications for a specific variable
    variable = 'AvgEarnings'
    print(f"\nStep 2: Analyzing replications for {variable}")
    
    # Make sure the variable exists in the dataframe
    if variable not in merged_df.columns:
        print(f"Error: Variable '{variable}' not found in the merged data.")
        print(f"Available columns: {', '.join(merged_df.columns.tolist())}")
        return
    
    # Set the relative precision to 10%
    relative_precision = 0.1
    
    print(f"Calculating replications needed to guarantee the actual {variable}")
    print(f"is within ±{relative_precision*100:.0f}% from the estimated average with 95% confidence.")
    
    # Calculate required replications
    try:
        results = calculate_replications(merged_df, variable, relative_precision)
        
        if not results:
            print(f"No valid configurations found for analysis.")
            return
        
        # Step 3: Generate and save report
        print("\nStep 3: Generating report")
        report = generate_report(results, variable)
        
        report_file = f"replication_analysis_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        with open(report_file, 'w') as f:
            f.write(report)
        print(f"Report saved to {report_file}")
        
        print("\nReport summary:")
        print(report)
        
        # Step 4: Create and save plots
        print("\nStep 4: Creating visualizations")
        plot_required_replications(results)
        plot_confidence_intervals(results, variable)
        
        print("\nAnalysis complete.")
        
    except Exception as e:
        print(f"Error during analysis: {str(e)}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()