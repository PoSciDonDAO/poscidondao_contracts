import numpy as np
import matplotlib.pyplot as plt

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
        cumulative_sci[12] += tokens_to_vest * 0.5  # Unlock 50% at 12 months
        cumulative_sci[36] += tokens_to_vest * 0.5  # Unlock remaining 50% at 36 months

    # Handle other vesting schedules (up to 18 months, linear vesting)
    elif vesting_months > 0 and vesting_months <= 18:
        monthly_vest = tokens_to_vest / vesting_months
        for month in range(1, vesting_months + 1):
            cumulative_sci[month] += monthly_vest

# Ensure cumulative tokens over time
cumulative_sci = np.cumsum(cumulative_sci)

# Plotting the graph
plt.figure(figsize=(10, 6))

# Transparent content and black background
plt.plot(months, cumulative_sci, color=(0, 0, 1, 0.8), marker='o', linestyle='-', label="Total Tokens in Circulation")
plt.fill_between(months, 0, cumulative_sci, color=(0, 0, 1, 0.4))  # Semi-transparent fill
plt.title("Total SCI Circulation After Launch", color="white", fontsize=14)
plt.xlabel("Time in Months After TGE", color="white", fontsize=12)
plt.ylabel("SCI Tokens in Circulation (Millions)", color="white", fontsize=12)
plt.xticks(np.arange(0, 37, 5), color="white")
plt.yticks(color="white")
plt.grid(False)
plt.legend(facecolor="black", edgecolor="white", labelcolor="white")
plt.gca().set_facecolor("black")  # Black background for the plot area
plt.gcf().set_facecolor("black")  # Black background for the figure
plt.tight_layout()
plt.show()
