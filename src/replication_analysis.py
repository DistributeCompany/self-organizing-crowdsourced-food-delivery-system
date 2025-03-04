import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
import math

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
    configurations = data['Configuration'].unique()
    
    for config in configurations:
        config_data = data[data['Configuration'] == config]
        values = config_data[variable].values
        
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
        absolute_precision = relative_precision * mean
        
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

def plot_required_replications(results):
    """
    Create a bar plot of the required replications for each configuration.
    
    Parameters:
    -----------
    results : dict
        The dictionary of results from calculate_replications
    
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
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    x = np.arange(len(configs))
    width = 0.35
    
    ax.bar(x - width/2, current_n, width, label='Current Replications')
    ax.bar(x + width/2, required_n, width, label='Required Replications')
    
    ax.set_ylabel('Number of Replications')
    ax.set_title('Required Replications for Desired Confidence Interval Width')
    ax.set_xticks(x)
    ax.set_xticklabels(configs)
    ax.legend()
    
    # Add value labels on bars
    for i, v in enumerate(current_n):
        ax.text(i - width/2, v + 0.1, str(v), ha='center')
    
    for i, v in enumerate(required_n):
        ax.text(i + width/2, v + 0.1, str(v), ha='center')
    
    fig.tight_layout()
    return fig

def plot_confidence_intervals(results, variable):
    """python replications_ each configuration.
    
    Parameters:
    -----------
    results : dict
        The dictionary of results from calculate_replications
    
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
        configs.append(config)
        means.append(result['mean'])
        lower_bounds.append(result['current_ci'][0])
        upper_bounds.append(result['current_ci'][1])
        half_widths.append(result['current_half_width'])
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
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
        ax.text(x[i], means[i] + hw + 50, f'Half-width: {hw:.2f}', ha='center')
    
    ax.set_ylabel(variable)
    ax.set_title(f'Confidence Intervals for {variable}')
    ax.set_xticks(x)
    ax.set_xticklabels(configs)
    ax.legend()
    
    fig.tight_layout()
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
        report += f"Current half-width of CI: {result['current_half_width']:.2f}\n"
        report += f"Current CI: ({result['current_ci'][0]:.2f}, {result['current_ci'][1]:.2f})\n"
        report += f"Target precision: {result['precision_percentage']} ({result['absolute_precision']:.4f})\n"
        report += f"Required replications: {result['required_replications']}\n"
        
        if result['required_replications'] <= result['current_sample_size']:
            report += "Status: ✓ Current replications are sufficient\n"
        else:
            additional = result['required_replications'] - result['current_sample_size']
            report += f"Status: ✗ Need {additional} more replications\n"
        
        report += "\n"
    
    return report

def main():
    """
    Main function to run the replication analysis.
    """
    # Load the data
    try:
        df = pd.read_csv('courier_experiment_results_10-27-20.688_am_04-Mar-2025.csv')
    except FileNotFoundError:
        print("Error: CSV file not found. Please check the file path.")
        return
    
    # Define the variable to analyze
    variable = 'AvgEarnings'
    
    # Set the absolute precision to 0.1
    absolute_precision = 0.1
    
    print(f"Calculating replications needed to guarantee the actual {variable}")
    print(f"is within ±{absolute_precision} from the estimated average with 95% confidence.")
    
    # Calculate required replications
    results = calculate_replications(df, variable, absolute_precision)
    
    # Generate and display report
    report = generate_report(results, variable)
    print(report)
    
    # Create plots
    fig1 = plot_required_replications(results)
    fig2 = plot_confidence_intervals(results, variable)
    
    # Save plots
    fig1.savefig('required_replications.png')
    fig2.savefig('confidence_intervals.png')
    
    print("Analysis complete. Plots saved as 'required_replications.png' and 'confidence_intervals.png'.")

if __name__ == "__main__":
    main()