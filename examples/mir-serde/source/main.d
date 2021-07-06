import dyaml;

import mir.algebraic_alias.json;
import mir.format;
import mir.ion.conv: json2ion;
import mir.ion.deser.ion: deserializeIon;
import mir.ion.ser.ion: serializeIon;
import mir.ion.ser.json: serializeJsonPretty;
import mir.serde;

static immutable yaml = `
    type: request
    value: 123.4
    name: "London"
`;

struct S
{
    enum Type {
        response,
        request,
    }

    private this(Type type, string name, JsonAlgebraic value) {
        this.type = type;
        this._name = name;
        this.value = value;
    }

    Type type;

    private string _name;

    @serdeKeys("name")
    void setName(string name) @property
    {
        _name = name;
    }

    @serdeKeys("name")
    auto getName() @property
    {
        return _name;
    }

    JsonAlgebraic value;
}

static immutable json = "{
\t\"type\": \"request\",
\t\"value\": 123.4,
\t\"name\": \"London\"
}";

import std.stdio;

void main()
{
    assert(Loader.fromString(yaml).load().serializeJsonPretty == json);
    auto s = Loader.fromString(yaml).load().serializeIon.deserializeIon!S;
    assert(s == S(S.Type.request, "London", JsonAlgebraic(123.4)));

    auto app = stringBuf();
    Dumper().dump(&app, json.json2ion.deserializeIon!Node);
    auto yamlData = app.data.idup;
    import std.stdio;
    writeln(s);
    writeln(yamlData);
}
