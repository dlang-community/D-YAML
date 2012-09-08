
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML serializer.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.serializer;


import std.array;
import std.format;
import std.typecons;

import dyaml.anchor;
import dyaml.emitter;
import dyaml.encoding;
import dyaml.event;
import dyaml.exception;
import dyaml.node;
import dyaml.resolver;
import dyaml.tag;
import dyaml.tagdirective;
import dyaml.token;


package:

///Serializes represented YAML nodes, generating events which are then emitted by Emitter.
struct Serializer
{
    private:
        ///Emitter to emit events produced.
        Emitter* emitter_;
        ///Resolver used to determine which tags are automaticaly resolvable.
        Resolver resolver_;

        ///Do all document starts have to be specified explicitly?
        bool explicitStart_;
        ///Do all document ends have to be specified explicitly?
        bool explicitEnd_;
        ///YAML version string.
        string YAMLVersion_;

        ///Tag directives to emit.
        TagDirective[] tagDirectives_;

        //TODO Use something with more deterministic memory usage.
        ///Nodes with assigned anchors.
        Anchor[Node] anchors_;
        ///Nodes with assigned anchors that are already serialized.
        bool[Node] serializedNodes_;
        ///ID of the last anchor generated.
        uint lastAnchorID_ = 0;

    public:
        /**
         * Construct a Serializer.
         *
         * Params:  emitter       = Emitter to emit events produced.
         *          resolver      = Resolver used to determine which tags are automaticaly resolvable. 
         *          encoding      = Character encoding to use.
         *          explicitStart = Do all document starts have to be specified explicitly? 
         *          explicitEnd   = Do all document ends have to be specified explicitly? 
         *          YAMLVersion   = YAML version string. 
         *          tagDirectives = Tag directives to emit. 
         */
        this(ref Emitter emitter, Resolver resolver, Encoding encoding,
             in bool explicitStart, in bool explicitEnd, string YAMLVersion, 
             TagDirective[] tagDirectives) @trusted
        {
            emitter_ = &emitter;
            resolver_ = resolver;
            explicitStart_ = explicitStart;
            explicitEnd_ = explicitEnd;
            YAMLVersion_ = YAMLVersion;
            tagDirectives_ = tagDirectives;

            emitter_.emit(streamStartEvent(Mark(), Mark(), encoding));
        }

        ///Destroy the Serializer.
        @safe ~this()
        {
            emitter_.emit(streamEndEvent(Mark(), Mark()));
            clear(YAMLVersion_);
            YAMLVersion_ = null;
            clear(serializedNodes_);
            serializedNodes_ = null;
            clear(anchors_);
            anchors_ = null;
        }

        ///Serialize a node, emitting it in the process.
        void serialize(ref Node node) @safe
        {
            emitter_.emit(documentStartEvent(Mark(), Mark(), explicitStart_, 
                                             YAMLVersion_, tagDirectives_));
            anchorNode(node);
            serializeNode(node);
            emitter_.emit(documentEndEvent(Mark(), Mark(), explicitEnd_));
            clear(serializedNodes_);
            clear(anchors_);
            Anchor[Node] emptyAnchors;
            anchors_ = emptyAnchors;
            lastAnchorID_ = 0;
        }

    private:
        /**
         * Determine if it's a good idea to add an anchor to a node.
         *
         * Used to prevent associating every single repeating scalar with an 
         * anchor/alias - only nodes long enough can use anchors.
         *
         * Params:  node = Node to check for anchorability.
         *
         * Returns: True if the node is anchorable, false otherwise.
         */
        static bool anchorable(ref Node node) @safe 
        {
            if(node.isScalar)
            {
                return node.isType!string    ? node.as!string.length > 64 :
                       node.isType!(ubyte[]) ? node.as!(ubyte[]).length > 64:
                                               false;
            }
            return node.length > 2;
        }

        ///Add an anchor to the node if it's anchorable and not anchored yet.
        void anchorNode(ref Node node) @safe
        {
            if(!anchorable(node)){return;}

            if((node in anchors_) !is null)
            {
                if(anchors_[node].isNull())
                {
                    anchors_[node] = generateAnchor();
                }
                return;
            }

            anchors_[node] = Anchor(null);
            if(node.isSequence) foreach(ref Node item; node)
            {
                anchorNode(item);
            }
            else if(node.isMapping) foreach(ref Node key, ref Node value; node)
            {
                anchorNode(key);
                anchorNode(value);
            }
        }

        ///Generate and return a new anchor.
        Anchor generateAnchor() @trusted
        {
            ++lastAnchorID_;
            auto appender = appender!string;
            formattedWrite(appender, "id%03d", lastAnchorID_);
            return Anchor(appender.data);
        }

        ///Serialize a node and all its subnodes.
        void serializeNode(ref Node node) @trusted
        {
            //If the node has an anchor, emit an anchor (as aliasEvent) on the 
            //first occurrence, save it in serializedNodes_, and emit an alias 
            //if it reappears.
            Anchor aliased = Anchor(null);
            if(anchorable(node) && (node in anchors_) !is null)
            {
                aliased = anchors_[node];
                if((node in serializedNodes_) !is null)
                {
                    emitter_.emit(aliasEvent(Mark(), Mark(), aliased));
                    return;
                }
                serializedNodes_[node] = true;
            }

            if(node.isScalar)
            {
                assert(node.isType!string, "Scalar node type must be string before serialized");
                auto value = node.as!string;
                const detectedTag = resolver_.resolve(NodeID.Scalar, Tag(null), value, true);
                const defaultTag = resolver_.resolve(NodeID.Scalar, Tag(null), value, false);
                bool isDetected = node.tag_ == detectedTag;
                bool isDefault = node.tag_ == defaultTag;

                emitter_.emit(scalarEvent(Mark(), Mark(), aliased, node.tag_,
                              tuple(isDetected, isDefault), value, node.scalarStyle));
                return;
            }
            if(node.isSequence)
            {
                const defaultTag = resolver_.defaultSequenceTag;
                const implicit = node.tag_ == defaultTag;
                emitter_.emit(sequenceStartEvent(Mark(), Mark(), aliased, node.tag_,
                                                 implicit, node.collectionStyle));
                foreach(ref Node item; node)
                {
                    serializeNode(item);
                }
                emitter_.emit(sequenceEndEvent(Mark(), Mark()));
                return;
            }
            if(node.isMapping)
            {
                const defaultTag = resolver_.defaultMappingTag; 
                const implicit = node.tag_ == defaultTag;
                emitter_.emit(mappingStartEvent(Mark(), Mark(), aliased, node.tag_,
                                                implicit, node.collectionStyle));
                foreach(ref Node key, ref Node value; node)
                { 
                    serializeNode(key);
                    serializeNode(value);
                }
                emitter_.emit(mappingEndEvent(Mark(), Mark()));
                return;
            }
            assert(false, "This code should never be reached");
        }
}
