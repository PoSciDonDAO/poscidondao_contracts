import matplotlib.pyplot as plt
import numpy as np

# Data
data = [
    {"tokens_circulation": 99526.32, "total_tokens": 1891000.00, "vesting_months": 18},
    {"tokens_circulation": 7273.08, "total_tokens": 94550.00, "vesting_months": 12},
    {"tokens_circulation": 7273.08, "total_tokens": 94550.00, "vesting_months": 12},
    {"tokens_circulation": 7273.08, "total_tokens": 94550.00, "vesting_months": 12},
    {"tokens_circulation": 7273.08, "total_tokens": 94550.00, "vesting_months": 12},
    {"tokens_circulation": 14546.16, "total_tokens": 189100.00, "vesting_months": 12},
    {"tokens_circulation": 14546.16, "total_tokens": 189100.00, "vesting_months": 12},
    {"tokens_circulation": 7091.25, "total_tokens": 70912.50, "vesting_months": 12},
    {"tokens_circulation": 7091.25, "total_tokens": 70912.50, "vesting_months": 12},
    {"tokens_circulation": 11346, "total_tokens": 28801.38, "vesting_months": 6},
    {"tokens_circulation": 6303.33, "total_tokens": 18910.00, "vesting_months": 3},
    {"tokens_circulation": 6303.33, "total_tokens": 18910.00, "vesting_months": 3},
    {"tokens_circulation": 18910, "total_tokens": 56730.00, "vesting_months": 3},
    {"tokens_circulation": 2909.24, "total_tokens": 90186.16, "vesting_months": 12},
    {"tokens_circulation": 2909.24, "total_tokens": 12364.24, "vesting_months": 12},
    {"tokens_circulation": 0, "total_tokens": 472750.00, "vesting_months": 36},
    {"tokens_circulation": 93604.5, "total_tokens": 312015.00, "vesting_months": 8},
    {"tokens_circulation": 6143.048571, "total_tokens": 43001.34, "vesting_months": 6},
    {"tokens_circulation": 1891, "total_tokens": 1891, "vesting_months": 0},
    {"tokens_circulation": 94550, "total_tokens": 94550, "vesting_months": 0},
    {"tokens_circulation": 2017712.4, "total_tokens": 2017712.4, "vesting_months": 0},
    {"tokens_circulation": 279683.83, "total_tokens": 279683.83, "vesting_months": 0}
]

# Initialize variables
months = np.arange(0, 37)
cumulative_sci = np.zeros_like(months, dtype=float)
monthly_vests = np.zeros_like(months, dtype=float)

# Add initial circulating tokens (Month 0)
tokens_in_circulation = sum(entry["tokens_circulation"] for entry in data)
cumulative_sci[0] = tokens_in_circulation

# Process vesting schedules for tokens to be vested
for entry in data:
    total_tokens = entry["total_tokens"]
    tokens_circulation = entry["tokens_circulation"]
    vesting_months = entry["vesting_months"]

    # Tokens remaining to be vested
    tokens_to_vest = total_tokens - tokens_circulation

    # Handle vesting for 36 months (special case: 50% at 12 months, 50% remainder at 36 months)
    if vesting_months == 36:
        monthly_vests[12] += tokens_to_vest * 0.5  # Unlock 50% at 12 months
        monthly_vests[36] += tokens_to_vest * 0.5  # Unlock remaining 50% at 36 months

    # Handle other vesting schedules (up to 18 months, linear vesting)
    elif vesting_months > 0 and vesting_months <= 18:
        monthly_vest = tokens_to_vest / vesting_months
        for month in range(1, vesting_months + 1):
            monthly_vests[month] += monthly_vest

# Ensure cumulative tokens over time
cumulative_sci = np.cumsum(monthly_vests)

# Prepare data for a single table with 6 columns
table_data = [[] for _ in range(6)]  # 6 columns
for month in range(1, 37):  # Months 1 to 36
    col_index = (month - 1) // 6  # Determine the column (0-5)
    table_data[col_index].append(f"Month {month}: {cumulative_sci[month]:,.2f}")

# Ensure all columns have equal length
max_rows = max(len(col) for col in table_data)
for col in table_data:
    while len(col) < max_rows:
        col.append("")  # Add empty strings to equalize column lengths

# Transpose the data for a table
table_data = list(zip(*table_data))

# Plotting the table
plt.figure(figsize=(12, 8))
table = plt.table(
    cellText=table_data,
    colLabels=[f"Column {i+1}" for i in range(6)],
    loc="center",
    cellLoc="center",
    rowLoc="center",
    colColours=["#0000FF"] * 6,  # Table header line color (0, 0, 1, 0.8)
    cellColours=[["#000000"] * 6 for _ in table_data],  # Black background for the cells
    fontsize=12,
    edges="closed"
)

# Style the table text with white color
for key, cell in table.get_celld().items():
    cell.set_text_props(color="white")

# Style the background of the plot
plt.gca().set_facecolor("black")  # Black background for the plot area
plt.gcf().set_facecolor("black")  # Black background for the figure
plt.axis('off')  # Turn off axis

# Add a title for clarity
plt.title("Cumulative Tokens Circulated Over 36 Months", fontsize=16, color="white")

plt.show()
