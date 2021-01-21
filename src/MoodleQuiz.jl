module MoodleQuiz

using LaTeXStrings
using FileIO
using LightXML
using HttpCommon
using Markdown
using OrderedCollections
using Base: @kwdef
using Pipe: @pipe
using Base64

import Base.show

export Question, Category, Quiz, moodle_xml, @cz_str, @en_str

export TrueFalse, True, False, YesNo, Yes, No, MultiChoice, SingleChoice, Choice
export Correct, Wrong, Essay, ShortAnswer, Numerical

## Helper functions
ensurearray(x) = if isa(x, Array); x else [ x ] end

function escape_chars(io::IO, s::AbstractString, chars)
    a = Iterators.Stateful(s)
    for c::AbstractChar in a
        if c in chars
            print(io, '\\', c)
        else
            print(io, c)
        end
    end
end

## Data types & contructors
@kwdef struct Text
    text::Markdown.MD
    lang::String
end
macro cz_str(text) return :( Text(text=Markdown.parse($text), lang="cs") ) end
macro en_str(text) return :( Text(text=Markdown.parse($text), lang="en") ) end

# Answer data types

abstract type Answer end

struct Essay <: Answer end

struct TrueFalse <: Answer
    correct::Bool
end

True() = TrueFalse(true)
False() = TrueFalse(false)

struct YesNo <: Answer
    yes::Bool
end

Yes() = YesNo(true)
No() = YesNo(false)

struct Choice
    correct::Bool
    content::Vector{Any}
end

Choice(content; correct::Bool) = Choice(correct, ensurearray(content))

Correct(content) = Choice(content, correct=true)
Wrong(content) = Choice(content, correct=false)

@enum AnswerNumbering none=0 abc=1 ABCD=2 numeric=3

@kwdef struct MultiChoice <: Answer
    single::Bool = false
    shuffle::Bool = true
    correct_feedback = ""
    partiallycorrectfeedback = ""
    incorrectfeedback = ""
    answernumbering::AnswerNumbering = none

    choices::Vector{Choice}
    # TODO: Enforce single correct choice if single==true
end

MultiChoice(choices; kwargs...) = MultiChoice(; choices, kwargs...)
SingleChoice(choices; kwargs...) = MultiChoice(; choices, single=true, kwargs...)

struct Numerical <: Answer
    val::Real
    tolerance::Real
end
Numerical(val) = Numerical(val, 0.0)

struct ShortAnswer <: Answer
    text::String
    fraction::Int               # 0 - 100 (or points for cloze)
end
ShortAnswer(text) = ShortAnswer(text, 100)

# Question, Category, Quiz

@kwdef struct Question
    id::String
    points::Float64
    dates::String
    content::Vector{Any}
    answer::Union{Answer, Nothing} = nothing

    responseformat::String = "editorfilepicker"
    responserequired::Bool = true
    responsefieldlines::Int64 = 5
    attachments::Int64 = 0
    attachmentsrequired::Int64 = 0
end

struct Category
    name::String
    questions::OrderedDict{String,Question}
end
Category(name) = Category(name, OrderedDict())
default_category = Category("")

Question(id, points, dates, content, answer=nothing; kwargs...) =
    Question(default_category, id, points, dates, content, answer, kwargs...)

function Question(category::Category, id, points, dates, content, answer=nothing; kwargs...)
    if isnothing(answer) && !any(typeof.(content) .<: Answer)
        answer = Essay()
    end
    q = Question(; id, points, dates, content, answer, kwargs...)
    category.questions[q.id] = q
    return q
end

@kwdef struct Quiz
    questions::Vector{Question} = [] # questions without category
    categories::Vector{Category} = [] # questions with category
end

Quiz(q::Question) = Quiz(questions=[q])
Quiz(c::Category) = Quiz(categories=[c])

## Preview methods

preview(io::IO, ::Nothing) = nothing
preview(io::IO, ::Essay) = print(io, "Essay")
preview(io::IO, ::ShortAnswer) = print(io, "ShortAnswer")
preview(io::IO, tf::TrueFalse) = print(io, "($(tf.correct ? "x" : " ")) True  ($(tf.correct ? " " : "x")) False")
preview(io::IO, yn::YesNo) = print(io, "($(yn.yes ? "x" : " ")) Yes  ($(yn.yes ? " " : "x")) No")
function preview(io::IO, choice::Choice)
    for val in choice.content
        print(io, repr("text/html", val))
    end
end


function preview(io::IO, mc::MultiChoice)
    print(io, "<ul>")
    for choice in mc.choices
        x = choice.correct ? "x" : " "
        print(io, "<li>" * (mc.single ? "($x)" : "[$x]") * " ")
        preview(io, choice)
        print(io, "</li>")
    end
    println(io, "</ul>")
end

function preview(io::IO, q::Question)
    println(io, "<h3>Question $(q.id)</h3>")
    println(io, "<div class=points>Points: $(q.points)</div>")
    println(io, to_html(q))
    println(io, "<div class=answer>Answer: ")
    preview(io, q.answer)
    println(io, "</div>")
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

function Base.show(io::IO, ::MIME"text/html", t::Text)
    print(io, """<span lang="$(t.lang)" class="multilang">""" * repr("text/html", t.text) * "</span>")
end

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

# Cloze sub-questions
function cloze(type::String,
               answers::String;
               weight::Int = 1) # Why UInt doesn't work?
    " {$(weight):$(type):$(answers)} "
end
function cloze(type::String, answers::Vector{Choice}; kwargs...)
    ansstr = join(map(answers) do a
                  (a.correct ? "=" : "") *
                  # https://docs.moodle.org/310/en/Embedded_Answers_(Cloze)_question_type#Detailed_syntax_explanations
                  sprint(escape_chars, join(map(to_html, a.content)), "#~/\"\\")
                  end, "~")
    cloze(type, ansstr; kwargs...)
end
cloze_answer(answer, feedback) = "$answer#$feedback"
to_html(yn::YesNo) = cloze("MULTICHOICE", [Choice(yn.yes, ["Yes"]), Choice(!yn.yes, ["No"])])
to_html(sa::ShortAnswer) = cloze("SA", [Correct(sa.text)])
to_html(num::Numerical) = cloze("NUMERICAL", "=$(num.val):$(num.tolerance)")
to_html(mc::MultiChoice) = cloze("MULTICHOICE", "=TODO")

function to_html(x::LaTeXString)
    png = render_png(x)
    io = IOBuffer()
    iob64_encode = Base64EncodePipe(io);
    save(Stream(format"PNG", iob64_encode), png)
    """<img src="data:text/png;base64,$(String(take!(io)))">"""
end

to_html(a::Vector{Any}) = join(to_html.(a))

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

moodle_xml_type(::TrueFalse) = "truefalse"
moodle_xml_type(::ShortAnswer) = "shortanswer"
moodle_xml_type(::Numerical) = "numerical"
moodle_xml_type(::MultiChoice) = "multichoice"
moodle_xml_type(::YesNo) = "multichoice"
moodle_xml_type(::Essay) = "essay"
moodle_xml_type(x) = nothing

function moodle_xml_type(q::Question)
    type = moodle_xml_type(q.answer)
    if isnothing(type) && any(typeof.(q.content) .<: Answer)
        type = "cloze"
    end
   return type
end

function moodle_xml_answer(xquestion, text::String, fraction::Int; kwargs...)
    xans = new_child(xquestion, "answer")
    set_attribute(xans, "fraction", string(fraction))
    xtext = new_child(xans, "text")
    add_text(xtext, text)
    for (tag, val) in kwargs
        xtag = new_child(xans, tag)
        add_text(xtag, string(val))
    end
end

moodle_xml(tf::TrueFalse, xquestion) = begin
    moodle_xml_answer(xquestion, "true", tf.correct ? 100 : 0)
    moodle_xml_answer(xquestion, "false", !tf.correct ? 100 : 0)
end
moodle_xml(yn::YesNo, xquestion) = begin
    add(elem::String, val) = add_text(new_child(xquestion, elem), string(val))
    add("single", true)
    moodle_xml_answer(xquestion, "true", yn.yes ? 100 : 0)
    moodle_xml_answer(xquestion, "false", !yn.yes ? 100 : 0)
end
moodle_xml(na::Numerical, xquestion) = moodle_xml_answer(xquestion, na.val, 100, na.tolerance)
moodle_xml(sa::ShortAnswer, xquestion) = moodle_xml_answer(xquestion, sa.text, sa.fraction)
# TODO: Multiple short and numerical answers
moodle_xml(mc::MultiChoice, xquestion) = begin
    for c in mc.choices
        moodle_xml_answer(xquestion, to_html(c.content), c.correct ? 100 : 0)
    end

    add(elem::String, val) = add_text(new_child(xquestion, elem), string(val))

    add("single", mc.single)
    add("shuffleanswers", mc.shuffle)
    add("answernumbering", "none")
end
moodle_xml(a::Answer, xquestion) = nothing

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

    if q.answer != nothing
        moodle_xml(q.answer, xquestion)
    end

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
    for q in values(cat.questions)
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
    if default_category in quiz.categories
        for q in values(default_category.questions)
            moodle_xml(q, xroot)
        end
    end
    for cat in quiz.categories
        cat === default_category && continue
        moodle_xml(cat, xroot)
    end
    return xdoc
end

end
