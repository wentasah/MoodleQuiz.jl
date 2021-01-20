using MoodleQuiz
using Documenter

makedocs(;
    modules=[MoodleQuiz],
    authors="Michal Sojka <michal.sojka@cvut.cz> and contributors",
    repo="https://github.com/wentasah/MoodleQuiz.jl/blob/{commit}{path}#L{line}",
    sitename="MoodleQuiz.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://wentasah.github.io/MoodleQuiz.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/wentasah/MoodleQuiz.jl",
)
