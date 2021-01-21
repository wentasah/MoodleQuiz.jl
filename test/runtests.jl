using MoodleQuiz
using MoodleQuiz: moodle_xml_type
using Test

@testset "MoodleQuiz.jl" begin

    q = Question("shortanswer", 1, "", [ "What time is it?" ],
                 ShortAnswer("13:49"))
    @test moodle_xml_type(q) == "shortanswer"

    q = Question("essay", 1, "", [ "What did you do today?" ] )
    @test typeof(q.answer) == Essay
    @test moodle_xml_type(q) == "essay"

    q = Question("multilang essay", 1, "",
                 [
                     en"What time is it?"
                     cz"Kolik je hodin?"
                 ])

    q = Question("true/false", 1, "",
                 [ "Julia is cool." ],
                 True())
    @test typeof(q.answer) == TrueFalse
    @test moodle_xml_type(q) == "truefalse"

    q = Question("yes/no", 1, "",
                 [ "Is this question nice?" ],
                 Yes())
    @test moodle_xml_type(q) == "multichoice"

    q = Question("multichoice", 1, "",
                 [ "Moodle is (multiple of):" ],
                 MultiChoice([
                     Correct("LMS")
                     Correct("web application")
                     Wrong("Wiki")
                     Wrong("desktop application")
                 ]))
    moodle_xml(q)
    @test moodle_xml_type(q) == "multichoice"

    q = Question("singlechoice", 1, "",
                 [ "Moodle is (single of):" ],
                 SingleChoice([
                     Correct("LMS")
                     Wrong("Wiki")
                     Wrong("desktop application")
                 ]))
    @test moodle_xml_type(q) == "multichoice"

    q = Question("cloze", 1, "",
                 [
                    "Moodle is"
                    ShortAnswer("LMS <&>")
                      "Its first version was release in year"
                      Numerical(2002)
                     "Is this quiz in Moodle?"
                     Yes()
                 ])
    @test moodle_xml_type(q) == "cloze"

    # The escaping rules are documented here:
    # https://docs.moodle.org/310/en/Embedded_Answers_(Cloze)_question_type#Detailed_syntax_explanations
    # but either the documentation or our implementation is not
    # complete, because Moodle fails to import the question if the
    # characters are in different order :-(
    q = Question("escaped cloze", 1, "",
                 [
                     "Characters that must be escaped in cloze sub-question are (write them space separated)"
                     ShortAnswer("# ~ \" \\ /")
                 ])
    @test occursin("\\# \\~ \\\" \\\\ \\/", MoodleQuiz.to_html(q))

    moodle_xml(q)
    moodle_xml(MoodleQuiz.default_category)
    moodle_xml(Quiz())

    if isinteractive()
        using LightXML
        save_file(moodle_xml(MoodleQuiz.default_category), "questions.xml")
    end
end
