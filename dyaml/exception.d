
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///D:YAML exceptions and exception related code.
module dyaml.exception;


import std.algorithm;
import std.array;
import std.string;


///Base class for all exceptions thrown by D:YAML.
class YAMLException : Exception
{
    public:
        ///Construct a YAMLException with specified message.
        this(string msg){super(msg);}

    package:
        //Set name of the file that was being processed when this exception was thrown.
        @property name(in string name)
        {
            msg = name ~ ":\n" ~ msg;
        }
}

///Position in a YAML stream, used for error messages.
align(1) struct Mark
{
    private:
        ///Line number.
        ushort line_;
        ///Column number.
        ushort column_;

    public:
        ///Construct a Mark with specified line and column in the file.
        this(in uint line, in uint column)
        {
            line_   = cast(ushort)min(ushort.max, line);
            column_ = cast(ushort)min(ushort.max, column);
        }

        ///Get a string representation of the mark.
        string toString() const
        {
            //Line/column numbers start at zero internally, make them start at 1.
            string clamped(ushort v){return format(v + 1, v == ushort.max ? " or higher" : "");}
            return format("line ", clamped(line_), ",column ", clamped(column_));
        }
}

package:
//Base class of YAML exceptions with marked positions of the problem.
abstract class MarkedYAMLException : YAMLException
{
    //Construct a MarkedYAMLException with specified context and problem.
    this(string context, Mark contextMark, string problem, Mark problemMark)
    {
        string msg = context ~ '\n';
        if(contextMark != problemMark){msg ~= contextMark.toString() ~ '\n';}
        msg ~= problem ~ '\n' ~ problemMark.toString() ~ '\n';
        super(msg);
    }

    //Construct a MarkedYAMLException with specified problem.
    this(string problem, Mark problemMark)
    {
        super(problem ~ '\n' ~ problemMark.toString());
    }
}
