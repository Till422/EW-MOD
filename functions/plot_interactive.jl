fig = Figure()

slider = SliderGrid(
    fig[4,1:4],
    (label="CO₂ price", range=0:10:120, startvalue=0)
)


vals = lift(slider.sliders[1].value) do x
    m = run_model(x)
    generation = value.(m[:G])
    storage_gen = value.(m[:CH])
    curtailment = value.(m[:CU])
    storage_level = value.(m[:L])
    lost_load = value.(m[:LL])
    feedin = value.(m[:feedin])
    
    RES_NS = setdiff(RES, S)
    res_gen = sum(generation[intersect(RES_NS,DISP),:]) + sum(feedin[intersect(RES_NS,NDISP),:])
    
    NRES_NS = setdiff(NRES, S)
    nres_gen = sum(generation[intersect(NRES_NS,DISP),:]) + sum(feedin[intersect(NRES_NS,NDISP),:])

    res_share = round(res_gen*100/(nres_gen+res_gen), digits=1)

    power = value.(m[:POWER])
    storage = value.(m[:STORAGE])

    generation_combined = vcat(generation, feedin, lost_load.data')
    cum_generation = vcat(zeros(1, length(T)), cumsum(generation_combined, dims=1))

    cum_charge = vcat(
        zeros(1, length(T)),
        -cumsum(vcat(storage_gen.data, curtailment.data'), dims=1)
    )

    return cum_generation, cum_charge, storage_level, power, storage, res_share
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
res_share = lift(x-> "res share = $(x[6]) %", vals)

ax = Axis(fig[2, 1:2], ylabel = "GW", xlabel="Hours", title=res_share)
colors = ["black", "brown", "grey",  "yellow", "cyan",  "blue", "red"]
  #color=["pp1", "pp2", "battery", "PV",    "wind",  "hydro", "lost load"]


labels = vcat(string.(P), "Lost load")

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


colors2 = ["grey","blue", "purple"]
#colors2 = ["battery","hydro", "curtailment"]
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
    demand.data,
    color=:black,
    label="Demand",
    linewidth=2
)
push!(legend_items, p_demand)
push!(legend_items_labels, "Demand")


ax2 = Axis(fig[3,1:2], ylabel = "GWh", title="Storage levels", height=120)
for (i,s) in enumerate(S)
    lines!(ax2, storage_level[i], color=colors2[i])
end


ax3 = Axis(
    fig[2:3,3],
    title="Capacity",
    xticks=(1:length(P), P),
    ylabel="GW",
    xticklabelrotation=pi/4
)

barplot!(
    ax3,
    power,
    color=["black", "brown", "grey", "yellow", "cyan", "blue"]
    #color=["pp1", "pp2", "battery", "PV", "wind",  "hydro"]
)

ax4 = Axis(
    fig[2:3,4],
    title="Storage",
    xticks=(1:length(S), S),
    ylabel="GWh",
    xticklabelrotation=pi/4
)

barplot!(
    ax4,
    storage,
    color=["grey","blue"]
)


Legend(
    fig[1,1:4],
    legend_items,
    legend_items_labels,
    orientation = :horizontal,
    nbanks = 1
)

on(rowcumgen[1][1]) do x
    autolimits!(ax)
end

on(storage_level[1]) do x
    autolimits!(ax2)
end

on(power) do x
    autolimits!(ax3)
end

on(storage) do x
    autolimits!(ax4)
end

fig