color_dict = Dict(
    "battery" => "#8e8eb5",
    "hydro"  => "blue",
    "pv" => "#ffeb3b",
    "wind" => "#518696",
    "lost load" => "#99002b",
    "curtailment" => "#99002b",
    "demand" => "#dad8ff",
    "seasonal storage" => "#00b3c7",
    "buy" => "#9526b7",
    "sell" => "#9526b7"
)

function interactive_plot()
    
    fig = Figure()

    slider = SliderGrid(
        fig[1,1],
        (label="Scenario", range=1:length(SCEN), startvalue=1)
    )

    vals = lift(slider.sliders[1].value) do x
        scen = SCEN[x]
        generation = value.(m[:G][scen,:,:])
        storage_gen = value.(m[:CH][scen,:,:])
        curtailment = value.(m[:CU][scen,:])
        storage_level = value.(m[:L][scen,:,:])
        lost_load = value.(m[:LL][scen,:])
        feedin = value.(m[:feedin][scen,:,:])

        if haskey(m, :BUY)
            buy = value.(m[:BUY][scen,:])
        else
            buy = DenseAxisArray(zeros(length(T)), T)
        end

        if haskey(m, :SELL)
            sell = value.(m[:SELL][scen,:])
        else
            sell = DenseAxisArray(zeros(length(T)), T)
        end

        power = value.(m[:POWER])
        storage = value.(m[:STORAGE])

        generation_combined = vcat(generation, feedin, buy', lost_load.data')
        cum_generation = vcat(zeros(1, length(T)), cumsum(generation_combined, dims=1))

        charged_combined = vcat(storage_gen.data, sell',  curtailment.data')
        cum_charge = vcat(
            zeros(1, length(T)),
            -cumsum(charged_combined, dims=1)
        )

        d = demand[scen[1],:]
        total_gen = sum(generation_combined, dims=2)[:]
        total_demand = sum(vcat(d', charged_combined), dims=2)[:]

        total = vcat(total_gen, total_demand) ./ 1e3

        return cum_generation, cum_charge, storage_level, power, storage, scen, d, total
    end

    rowcumgen = map(1:size(vals[][1], 1)-1) do row
        lower = lift(x-> x[1][row,:], vals)
        upper = lift(x-> x[1][row+1,:], vals)
        return (lower, upper)
    end

    rowcumdem = map(1:size(vals[][2], 1)-1) do row
        lower = lift(x-> x[2][row,:], vals)
        upper = lift(x-> x[2][row+1,:], vals)
        return (lower, upper)
    end

    storage_level = map(1:size(vals[][3], 1)) do row
        return lift(x-> x[3][S[row], :].data, vals)
    end

    power = lift(x-> x[4].data, vals)
    storage = lift(x-> x[5].data, vals)
    scen = lift(x-> "$(x[6])", vals)
    d = lift(x-> x[7].data, vals)

    total = lift(x-> x[8], vals)

    ax = Axis(fig[2, 1], ylabel = "MW", xlabel="Hours", title=scen)
    colors = vcat(
        [color_dict[p] for p in P],
        color_dict["buy"],
        color_dict["lost load"]
    )
    labels = vcat(string.(P), "Buy", "Lost load")

    legend_items = []
    legend_items_labels = String[]
    for row in 1:length(rowcumgen)
        b = band!(
            ax,
            1:length(T),
            rowcumgen[row][1],
            rowcumgen[row][2],
            color=(colors[row], 0.8),
            linewidth=0
        )
        push!(legend_items, b)
        push!(legend_items_labels, labels[row])
    end


    colors2 = vcat(
        [color_dict[s] for s in S],
        color_dict["sell"],
        color_dict["curtailment"]
    )

    for row in 1:length(rowcumdem)
        b = band!(
            ax,
            1:length(T),
            rowcumdem[row][1],
            rowcumdem[row][2],
            color=(colors2[row], 0.8),
            linewidth=0
        )
        row == length(rowcumdem) && push!(legend_items, b)
    end

    push!(legend_items_labels, "Curtailment")

    hlines!(ax, 0, color=:black, linewidth=2)

    p_demand = lines!(
        ax,
        d,
        color=:black,
        label="Demand",
        linewidth=2
    )
    push!(legend_items, p_demand)
    push!(legend_items_labels, "Demand")


    ax2 = Axis(fig[3,1], ylabel = "MWh", title="Storage levels", height=120)
    for (i,s) in enumerate(S)
        lines!(ax2, storage_level[i], color=colors2[i])
    end

    ax3 = Axis(
        fig[2,2],
        title="Generation",
        xticks=(1:2, ["Generation", "Consumption"]),
        ylabel="GWh"
    )


    labels = [P..., "buy", "lost load", "demand", S..., "sell", "curtailment"]
    stack_group = Int64[]
    pos_label_dict = Dict{Int64, String}()
    let i = 1, labels_pos_dict = Dict{String, Int64}()
        for l in labels
            if haskey(labels_pos_dict, l)
                push!(stack_group, labels_pos_dict[l])
            else
                push!(labels_pos_dict, l => i)
                push!(stack_group, i)
                push!(pos_label_dict, i => l)
                i += 1
            end
        end
    end

    barplot!(
        ax3,
        vcat(ones(Int, length(P)+1), fill(2, length(rowcumdem)+2)),
        total,
        stack=stack_group,
        color=map(x-> color_dict[pos_label_dict[x]], stack_group)
    )

    ax5 = Axis(
        fig[3,2],
        title="Capacity",
        xticks=(1:length(P), P),
        ylabel="MW",
        xticklabelrotation=pi/4
    )

    barplot!(
        ax5,
        power,
        color=[ "#8e8eb5", "blue", "#ffeb3b", "#518696"]
        #color=["batt", "#hydro", "#pv",     "wind"]
    )

    ax6 = Axis(
        fig[3,3],
        title="Storage capacity",
        xticks=(1:length(S), S),
        ylabel="MWh",
        xticklabelrotation=pi/4
    )

    barplot!(
        ax6,
        storage,
        color=["#8e8eb5","blue"]
    )

    colsize!(fig.layout, 1, Relative(2/3))
    colsize!(fig.layout, 3, Relative(1/8))

    Legend(
        fig[1,2:3],
        legend_items,
        legend_items_labels,
        orientation = :horizontal,
        nbanks = 3,
    )

    on(slider.sliders[1].value) do x
        autolimits!(ax)
    end

    on(slider.sliders[1].value) do x
        autolimits!(ax2)
    end

    on(slider.sliders[1].value) do x
        autolimits!(ax5)
    end

    on(slider.sliders[1].value) do x
        autolimits!(ax6)
    end

    on(slider.sliders[1].value) do x
        autolimits!(ax3)
    end

    return fig
end
