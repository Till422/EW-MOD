
function plot_result()
        
    generation = value.(m[:G])
    storage_gen = value.(m[:CH])
    curtailment = value.(m[:CU])
    storage_level = value.(m[:L])
    lost_load = value.(m[:LL])

    power = value.(m[:POWER])
    storage = value.(m[:STORAGE])

    generation_combined = vcat(generation, value.(m[:feedin]), lost_load.data')
    cum_generation = vcat(zeros(1, length(T)), cumsum(generation_combined, dims=1))

    cum_charge = vcat(
        zeros(1, length(T)),
        -cumsum(vcat(storage_gen.data, curtailment.data'), dims=1)
    )

    fig = Figure()
    ax = Axis(fig[2, 1:2], ylabel = "GW", xlabel="Hours")
    colors = ["#754937", "#e54213", "#8e8eb5", "#ffeb3b", "#518696", "#99002b"]
    labels = vcat(string.(P), "Lost load")

    legend_items = []
    legend_items_labels = String[]
    for row in 1:size(cum_generation, 1)-1
        b = band!(
            ax,
            1:length(T),
            cum_generation[row,:],
            cum_generation[row+1,:],
            color=(colors[row], 0.8),
            linewidth=0
        )
        push!(legend_items, b)
        push!(legend_items_labels, labels[row])
    end

    colors2 = ["#8e8eb5", "#ae123a"]
    for row in 1:size(cum_charge, 1)-1
        b = band!(
            ax,
            1:length(T),
            cum_charge[row,:],
            cum_charge[row+1,:],
            color=(colors2[row], 0.8),
            linewidth=0
        )
        row == size(cum_charge, 1)-1 && push!(legend_items, b)
    end

    push!(legend_items_labels, "Curtailment")

    hlines!(ax, 0, color=:black, linewidth=2)

    p_demand = lines!(
        ax,
        demand.data,
        color=:black,
        label="Demand",
        linewidth=2
    )
    push!(legend_items, p_demand)
    push!(legend_items_labels, "Demand")

    ax2 = Axis(fig[3,1:2], ylabel = "GWh", title="Storage levels", height=120)
    for (i,s) in enumerate(S)
        lines!(ax2, storage_level[s,:].data, color=colors2[i])
    end

    power_ticks = axes(power, 1)
    ax3 = Axis(
        fig[2:3,3],
        title="Capacity",
        xticks=(1:length(power_ticks), power_ticks),
        ylabel="GW",
        xticklabelrotation=pi/4
    )

    barplot!(
        ax3,
        power.data,
        color=["#754937", "#e54213", "#8e8eb5", "#ffeb3b", "#518696"]
    )

    storage_ticks = axes(storage, 1)
    ax4 = Axis(
        fig[2:3,4],
        title="Storage",
        xticks=(1:length(storage_ticks), storage_ticks),
        ylabel="GWh",
        xticklabelrotation=pi/4
    )

    barplot!(
        ax4,
        storage.data,
        color=["#8e8eb5"]
    )


    Legend(
        fig[1,1:4],
        legend_items,
        legend_items_labels,
        orientation = :horizontal,
        nbanks = 1
    )

    return fig
end
