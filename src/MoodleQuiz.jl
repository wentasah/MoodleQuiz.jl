module MoodleQuiz

using LaTeXStrings
using FileIO
using LightXML
using HttpCommon
using Markdown
using Base: @kwdef
using Pipe: @pipe
using Base64

import Base.show

export Question, Category, Quiz, moodle_xml, @cz_str, @en_str

@kwdef struct Text
    text::Markdown.MD
    lang::String
end

@kwdef struct Question
    id::String
    points::Float64
    dates::String
    content::Vector{Any}

    responseformat::String = "editorfilepicker"
    responserequired::Bool = true
    responsefieldlines::Int64 = 5
    attachments::Int64 = 0
    attachmentsrequired::Int64 = 0
end

struct Category
    name::String
    questions::Vector{Question}
end

Category(name) = Category(name, [])

Question(id, points, dates, content; kwargs...) = Question(; id=id, points=points, dates=dates, content=content, kwargs...)

function Question(category::Category, id, points, dates, content; kwargs...)
    q = Question(; id=id, points=points, dates=dates, content=content, kwargs...)
    push!(category.questions, q)
    return q
end

@kwdef struct Quiz
    questions::Vector{Question} = [] # questions without category
    categories::Vector{Category} = [] # questions with category
end

Quiz(q::Question) = Quiz(questions=[q])
Quiz(c::Category) = Quiz(categories=[c])

function Base.show(io::IO, ::MIME"text/html", t::Text)
    print(io, """<span lang="$(t.lang)" class="multilang">""" * repr("text/html", t.text) * "</span>")
end

macro cz_str(text) return :( Text(text=Markdown.parse($text), lang="cs") ) end
macro en_str(text) return :( Text(text=Markdown.parse($text), lang="en") ) end

function render_png(s::LaTeXString; dpi=150, debug=false, name=tempname(cleanup=false))
    doc = """
    \\documentclass[varwidth=100cm]{standalone}
    \\usepackage{tikz}
    \\usetikzlibrary{arrows.meta}
    \\usepackage{amssymb}
    \\usepackage{amsmath}
    \\begin{document}
    {
        $s
    }
    \\end{document}
    """
    doc = replace(doc, "\\begin{align}"=>"\\[\n\\begin{aligned}")
    doc = replace(doc, "\\end{align}"=>"\\end{aligned}\n\\]")
    try
        open("$(name).tex", "w") do f
            write(f, doc)
        end
        cd(dirname(name)) do
            cmd = `lualatex --interaction=$(debug ? "nonstopmode" : "batchmode") $(name).tex`
            debug || (cmd = pipeline(cmd, devnull))
            run(cmd)
            pdftoppm = run(`pdftoppm -r $(dpi) -png $(name).pdf $(name)`)
        end
        return load("$(name)-1.png")
    finally
        Base.Filesystem.rm("$(name).tex")
        Base.Filesystem.rm("$(name).pdf")
        Base.Filesystem.rm("$(name)-1.png")
    end
end

to_html(x) = repr("text/html", x)

function to_html(x::LaTeXString)
    png = render_png(x)
    io = IOBuffer()
    iob64_encode = Base64EncodePipe(io);
    save(Stream(format"PNG", iob64_encode), png)
    """<img src="data:text/png;base64,$(String(take!(io)))">"""
end

function preview(io::IO, q::Question)
    println(io, "<h3>Question $(q.id)</h3>")
    println(io, "<div class=points>Points: $(q.points)</div>")
    println(io, to_html(q))
end

function preview(io::IO, cat::Category)
    println(io, "<h2>Category $(cat.name)</h2>")
    for q in cat.questions
        preview(io, q)
    end
end

function preview(io::IO, quiz::Quiz)
    println(io, "<h1>Quiz</h1>")
    for q in quiz.questions
        preview(io, q)
    end
    for cat in quiz.categories
        preview(io, cat)
    end
end

function preview(object)
    open("questions.html", "w") do io
        preview(io, object)
    end
    run(`firefox-reload`)
end

function Base.show(io::IO, ::MIME"text/html", q::Question)
    for el in q.content
        print(io, to_html(el))
    end
end

function Base.show(io::IO, ::MIME"text/plain", q::Question)
    println(io, "Question($(q.id))")

    # FIXME: Not very generic way of quickly previewing the question
    preview(q)
end


moodle_xml_type(q::Question) = "essay"

function moodle_xml(q::Question, xroot)
    xquestion = new_child(xroot, "question")
    # Set the type
    set_attribute(xquestion, "type", moodle_xml_type(q))

    name = new_child(new_child(xquestion, "name"), "text")
    add_text(name, q.id)

    # Put the question text
    questiontext = new_child(xquestion, "questiontext")
    set_attribute(questiontext, "format", "html")
    text = new_child(questiontext, "text")
    add_text(text, repr("text/html", q))

    add(elem::String, val) = add_text(new_child(xquestion, elem), string(val))
    add(elem::String, val::Bool) = add(elem, Int(val))

    add("defaultgrade", q.points)
    add("responseformat", q.responseformat)
    add("responserequired", q.responserequired)
    add("responsefieldlines", q.responsefieldlines)
    add("attachments", q.attachments)
    add("attachmentsrequired", q.attachmentsrequired)
end

function moodle_xml(cat::Category, xroot)
    xquestion = new_child(xroot, "question")
    # Set the type
    set_attribute(xquestion, "type", "category")
    @pipe xquestion |> new_child(_, "category") |> new_child(_, "text") |> add_text(_, "\$course\$/top/$(cat.name)")
    for q in cat.questions
        moodle_xml(q, xroot)
    end
end


moodle_xml(q::Question) = moodle_xml(Quiz(q))
moodle_xml(c::Category) = moodle_xml(Quiz(c))

function moodle_xml(quiz::Quiz)::XMLDocument
    xdoc = XMLDocument()
    # Create test
    xroot = create_root(xdoc, "quiz")
    for q in quiz.questions
        moodle_xml(q, xroot)
    end
    for cat in quiz.categories
        moodle_xml(cat, xroot)
    end
    return xdoc
end

end
