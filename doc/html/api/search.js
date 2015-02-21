"use strict";
var items = [
{"dyaml.node" : "dyaml/node.html"},
{"dyaml.node.NodeException" : "dyaml/node/NodeException.html"},
{"dyaml.node.YAMLNull" : "dyaml/node/YAMLNull.html"},
{"dyaml.node.YAMLNull.toString" : "dyaml/node/YAMLNull.html#toString"},
{"dyaml.node.Node" : "dyaml/node/Node.html"},
{"dyaml.node.Node.this" : "dyaml/node/Node.html#this"},
{"dyaml.node.Node.this" : "dyaml/node/Node.html#this"},
{"dyaml.node.Node.this" : "dyaml/node/Node.html#this"},
{"dyaml.node.Node.this" : "dyaml/node/Node.html#this"},
{"dyaml.node.Node.this" : "dyaml/node/Node.html#this"},
{"dyaml.node.Node.isValid" : "dyaml/node/Node.html#isValid"},
{"dyaml.node.Node.isScalar" : "dyaml/node/Node.html#isScalar"},
{"dyaml.node.Node.isSequence" : "dyaml/node/Node.html#isSequence"},
{"dyaml.node.Node.isMapping" : "dyaml/node/Node.html#isMapping"},
{"dyaml.node.Node.isUserType" : "dyaml/node/Node.html#isUserType"},
{"dyaml.node.Node.isNull" : "dyaml/node/Node.html#isNull"},
{"dyaml.node.Node.tag" : "dyaml/node/Node.html#tag"},
{"dyaml.node.Node.opEquals" : "dyaml/node/Node.html#opEquals"},
{"dyaml.node.Node.as" : "dyaml/node/Node.html#as"},
{"dyaml.node.Node.get" : "dyaml/node/Node.html#get"},
{"dyaml.node.Node.get" : "dyaml/node/Node.html#get"},
{"dyaml.node.Node.length" : "dyaml/node/Node.html#length"},
{"dyaml.node.Node.opIndex" : "dyaml/node/Node.html#opIndex"},
{"dyaml.node.Node.contains" : "dyaml/node/Node.html#contains"},
{"dyaml.node.Node.containsKey" : "dyaml/node/Node.html#containsKey"},
{"dyaml.node.Node.opAssign" : "dyaml/node/Node.html#opAssign"},
{"dyaml.node.Node.opAssign" : "dyaml/node/Node.html#opAssign"},
{"dyaml.node.Node.opIndexAssign" : "dyaml/node/Node.html#opIndexAssign"},
{"dyaml.node.Node.opApply" : "dyaml/node/Node.html#opApply"},
{"dyaml.node.Node.opApply" : "dyaml/node/Node.html#opApply"},
{"dyaml.node.Node.add" : "dyaml/node/Node.html#add"},
{"dyaml.node.Node.add" : "dyaml/node/Node.html#add"},
{"dyaml.node.Node.opBinaryRight" : "dyaml/node/Node.html#opBinaryRight"},
{"dyaml.node.Node.remove" : "dyaml/node/Node.html#remove"},
{"dyaml.node.Node.removeAt" : "dyaml/node/Node.html#removeAt"},
{"dyaml.node.Node.opCmp" : "dyaml/node/Node.html#opCmp"},
{"dyaml.resolver" : "dyaml/resolver.html"},
{"dyaml.resolver.Resolver" : "dyaml/resolver/Resolver.html"},
{"dyaml.resolver.Resolver.this" : "dyaml/resolver/Resolver.html#this"},
{"dyaml.resolver.Resolver.addImplicitResolver" : "dyaml/resolver/Resolver.html#addImplicitResolver"},
{"dyaml.resolver.Resolver.defaultScalarTag" : "dyaml/resolver/Resolver.html#defaultScalarTag"},
{"dyaml.resolver.Resolver.defaultSequenceTag" : "dyaml/resolver/Resolver.html#defaultSequenceTag"},
{"dyaml.resolver.Resolver.defaultMappingTag" : "dyaml/resolver/Resolver.html#defaultMappingTag"},
{"dyaml.hacks" : "dyaml/hacks.html"},
{"dyaml.hacks.scalarStyleHack" : "dyaml/hacks.html#scalarStyleHack"},
{"dyaml.hacks.collectionStyleHack" : "dyaml/hacks.html#collectionStyleHack"},
{"dyaml.hacks.scalarStyleHack" : "dyaml/hacks.html#scalarStyleHack"},
{"dyaml.hacks.collectionStyleHack" : "dyaml/hacks.html#collectionStyleHack"},
{"dyaml.dumper" : "dyaml/dumper.html"},
{"dyaml.dumper.Dumper" : "dyaml/dumper/Dumper.html"},
{"dyaml.dumper.Dumper.this" : "dyaml/dumper/Dumper.html#this"},
{"dyaml.dumper.Dumper.this" : "dyaml/dumper/Dumper.html#this"},
{"dyaml.dumper.Dumper.name" : "dyaml/dumper/Dumper.html#name"},
{"dyaml.dumper.Dumper.resolver" : "dyaml/dumper/Dumper.html#resolver"},
{"dyaml.dumper.Dumper.representer" : "dyaml/dumper/Dumper.html#representer"},
{"dyaml.dumper.Dumper.canonical" : "dyaml/dumper/Dumper.html#canonical"},
{"dyaml.dumper.Dumper.indent" : "dyaml/dumper/Dumper.html#indent"},
{"dyaml.dumper.Dumper.textWidth" : "dyaml/dumper/Dumper.html#textWidth"},
{"dyaml.dumper.Dumper.lineBreak" : "dyaml/dumper/Dumper.html#lineBreak"},
{"dyaml.dumper.Dumper.encoding" : "dyaml/dumper/Dumper.html#encoding"},
{"dyaml.dumper.Dumper.explicitStart" : "dyaml/dumper/Dumper.html#explicitStart"},
{"dyaml.dumper.Dumper.explicitEnd" : "dyaml/dumper/Dumper.html#explicitEnd"},
{"dyaml.dumper.Dumper.YAMLVersion" : "dyaml/dumper/Dumper.html#YAMLVersion"},
{"dyaml.dumper.Dumper.tagDirectives" : "dyaml/dumper/Dumper.html#tagDirectives"},
{"dyaml.dumper.Dumper.dump" : "dyaml/dumper/Dumper.html#dump"},
{"dyaml.representer" : "dyaml/representer.html"},
{"dyaml.representer.RepresenterException" : "dyaml/representer/RepresenterException.html"},
{"dyaml.representer.Representer" : "dyaml/representer/Representer.html"},
{"dyaml.representer.Representer.this" : "dyaml/representer/Representer.html#this"},
{"dyaml.representer.Representer.defaultScalarStyle" : "dyaml/representer/Representer.html#defaultScalarStyle"},
{"dyaml.representer.Representer.defaultCollectionStyle" : "dyaml/representer/Representer.html#defaultCollectionStyle"},
{"dyaml.representer.Representer.addRepresenter" : "dyaml/representer/Representer.html#addRepresenter"},
{"dyaml.representer.Representer.representScalar" : "dyaml/representer/Representer.html#representScalar"},
{"dyaml.representer.Representer.representSequence" : "dyaml/representer/Representer.html#representSequence"},
{"dyaml.representer.Representer.representMapping" : "dyaml/representer/Representer.html#representMapping"},
{"dyaml.representer.representNull" : "dyaml/representer.html#representNull"},
{"dyaml.representer.representString" : "dyaml/representer.html#representString"},
{"dyaml.representer.representBytes" : "dyaml/representer.html#representBytes"},
{"dyaml.representer.representBool" : "dyaml/representer.html#representBool"},
{"dyaml.representer.representLong" : "dyaml/representer.html#representLong"},
{"dyaml.representer.representReal" : "dyaml/representer.html#representReal"},
{"dyaml.representer.representSysTime" : "dyaml/representer.html#representSysTime"},
{"dyaml.representer.representNodes" : "dyaml/representer.html#representNodes"},
{"dyaml.representer.representNodes.pairs" : "dyaml/representer.html#representNodes.pairs"},
{"dyaml.representer.representPairs" : "dyaml/representer.html#representPairs"},
{"dyaml.exception" : "dyaml/exception.html"},
{"dyaml.exception.YAMLException" : "dyaml/exception/YAMLException.html"},
{"dyaml.exception.YAMLException.this" : "dyaml/exception/YAMLException.html#this"},
{"dyaml.linebreak" : "dyaml/linebreak.html"},
{"dyaml.linebreak.LineBreak" : "dyaml/linebreak/LineBreak.html"},
{"dyaml.loader" : "dyaml/loader.html"},
{"dyaml.loader.Loader" : "dyaml/loader/Loader.html"},
{"dyaml.loader.Loader.this" : "dyaml/loader/Loader.html#this"},
{"dyaml.loader.Loader.fromString" : "dyaml/loader/Loader.html#fromString"},
{"dyaml.loader.Loader.this" : "dyaml/loader/Loader.html#this"},
{"dyaml.loader.Loader.name" : "dyaml/loader/Loader.html#name"},
{"dyaml.loader.Loader.resolver" : "dyaml/loader/Loader.html#resolver"},
{"dyaml.loader.Loader.constructor" : "dyaml/loader/Loader.html#constructor"},
{"dyaml.loader.Loader.load" : "dyaml/loader/Loader.html#load"},
{"dyaml.loader.Loader.loadAll" : "dyaml/loader/Loader.html#loadAll"},
{"dyaml.loader.Loader.opApply" : "dyaml/loader/Loader.html#opApply"},
{"dyaml.style" : "dyaml/style.html"},
{"dyaml.style.ScalarStyle" : "dyaml/style/ScalarStyle.html"},
{"dyaml.style.CollectionStyle" : "dyaml/style/CollectionStyle.html"},
{"dyaml.constructor" : "dyaml/constructor.html"},
{"dyaml.constructor.Constructor" : "dyaml/constructor/Constructor.html"},
{"dyaml.constructor.Constructor.this" : "dyaml/constructor/Constructor.html#this"},
{"dyaml.constructor.Constructor.addConstructorScalar" : "dyaml/constructor/Constructor.html#addConstructorScalar"},
{"dyaml.constructor.Constructor.addConstructorSequence" : "dyaml/constructor/Constructor.html#addConstructorSequence"},
{"dyaml.constructor.Constructor.addConstructorMapping" : "dyaml/constructor/Constructor.html#addConstructorMapping"},
{"dyaml.constructor.constructNull" : "dyaml/constructor.html#constructNull"},
{"dyaml.constructor.constructMerge" : "dyaml/constructor.html#constructMerge"},
{"dyaml.constructor.constructBool" : "dyaml/constructor.html#constructBool"},
{"dyaml.constructor.constructLong" : "dyaml/constructor.html#constructLong"},
{"dyaml.constructor.constructReal" : "dyaml/constructor.html#constructReal"},
{"dyaml.constructor.constructBinary" : "dyaml/constructor.html#constructBinary"},
{"dyaml.constructor.constructTimestamp" : "dyaml/constructor.html#constructTimestamp"},
{"dyaml.constructor.constructString" : "dyaml/constructor.html#constructString"},
{"dyaml.constructor.getPairs" : "dyaml/constructor.html#getPairs"},
{"dyaml.constructor.constructOrderedMap" : "dyaml/constructor.html#constructOrderedMap"},
{"dyaml.constructor.constructPairs" : "dyaml/constructor.html#constructPairs"},
{"dyaml.constructor.constructSet" : "dyaml/constructor.html#constructSet"},
{"dyaml.constructor.constructSequence" : "dyaml/constructor.html#constructSequence"},
{"dyaml.constructor.constructMap" : "dyaml/constructor.html#constructMap"},
];
function search(str) {
	var re = new RegExp(str.toLowerCase());
	var ret = {};
	for (var i = 0; i < items.length; i++) {
		var k = Object.keys(items[i])[0];
		if (re.test(k.toLowerCase()))
			ret[k] = items[i][k];
	}
	return ret;
}

function searchSubmit(value, event) {
	console.log("searchSubmit");
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	if (value === "" || event.keyCode == 27) {
		resultTable.style.display = "none";
		return;
	}
	resultTable.style.display = "block";
	var results = search(value);
	var keys = Object.keys(results);
	if (keys.length === 0) {
		var row = resultTable.insertRow();
		var td = document.createElement("td");
		var node = document.createTextNode("No results");
		td.appendChild(node);
		row.appendChild(td);
		return;
	}
	for (var i = 0; i < keys.length; i++) {
		var k = keys[i];
		var v = results[keys[i]];
		var link = document.createElement("a");
		link.href = v;
		link.textContent = k;
		link.attributes.id = "link" + i;
		var row = resultTable.insertRow();
		row.appendChild(link);
	}
}

function hideSearchResults(event) {
	if (event.keyCode != 27)
		return;
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	resultTable.style.display = "none";
}

