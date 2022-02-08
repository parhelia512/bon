using System;
using System.Collections;
using System.Diagnostics;
using System.Reflection;
using Bon.Integrated;

namespace Bon
{
	enum BonSerializeFlags : uint8
	{
		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields
		case IncludeNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		
		/// If two fields referenced the same class, this relationship will be preserved. Only the
		/// first occurrence will be serialized, the following ones will reference the first one.
		case KeepInnerReferences = 1 << 2;

		/// Ignore field attributes (only recommended for debugging / complete structure dumping)
		case IgnoreAttributes = 1 << 3;

		/// The produced string will be formatted (and slightly more verbose) for manual editing.
		case Verbose = 1 << 4;
	}

	enum BonDeserializeFlags : uint8
	{
		/// Fully set the state of the target structure based on the given string.
		case Default = 0;

		/// Values not mentioned in the given string will be left as they are
		/// instead of being nulled (and possibly deleted).
		case IgnoreUnmentionedValues = 1 | IgnorePointers;

		/// Ignore pointers when encountering them instead of erroring.
		/// Bon does not manipulate pointers.
		case IgnorePointers = 1 << 1;

		/// Allows bon strings to access non-public fields.
		case AccessNonPublic = 1 << 2;
	}
	
	public delegate void MakeThingFunc(ValueView refIntoVal);
	public delegate void DestroyThingFunc(ValueView valRef);

	public static function void HandleSerializeFunc(BonWriter writer, ref ValueView val, BonEnvironment env);
	public static function Result<void> HandleDeserializeFunc(BonReader reader, ref ValueView val, BonEnvironment env);

	/// Defines the behavior of bon. May be modified globally (gBonEnv)
	/// or for some calls only be creating a BonEnvironment to modify
	/// and passing that to calls for use instead of the global fallback.
	class BonEnvironment
	{
		public BonSerializeFlags serializeFlags;
		public BonDeserializeFlags deserializeFlags;

		/// When bon serializes or deserializes an unknown type, it checks this to see if there are custom
		/// functions to handle this type. Functions can be registered by type or by unspecialized generic
		/// type, like List<>. For examples, see SerializeHandlers.bf
		public Dictionary<Type, (HandleSerializeFunc serialize, HandleDeserializeFunc deserialize)> serializeHandlers = new .() ~ delete _;

		/// When bon needs to allocate or deallocate a reference type, a handler is called for it when possible
		/// instead of allocating with new or deleting. This can be used to gain more control over the allocation
		/// or specific types, for example to reference existing ones or register allocated instances elsewhere
		/// as well.
		/// Functions can be registered by type or by unspecialized generic type, like List<> but keep in mind
		/// that you need to deal with any specialized type indicated by the Variant. So you will probably still
		/// have to use CreateObjet, but you can manage the reference at least
		public Dictionary<Type, (MakeThingFunc make, DestroyThingFunc destroy)> instanceHandlers = new .() ~ {
			for (let p in _.Values)
			{
				if (p.make != null) delete p.make;
				if (p.destroy != null) delete p.destroy;
			}
			delete _;
		};

		/// Will be called for every deserialized StringView string. Must return a valid string view
		/// of the passed-in string.
		public function StringView(StringView view) stringViewHandler;

		// Collection of registered types used in polymorphism.
		// Required to get a type info from a serialized name.
		internal Dictionary<String, Type> polyTypes = new .() ~ DeleteDictionaryAndKeys!(_);

		public mixin RegisterPolyType(Type type)
		{
			Debug.Assert(type is TypeInstance, "Type not set up properly! Put [Serializable] on it or force reflection info & always include.");
			let str = type.GetFullName(.. new .());
			if (!polyTypes.ContainsKey(str))
				polyTypes.Add(str, type);
			else delete str;
		}

		public this()
		{
			if (gBonEnv == null)
				return;

			serializeFlags = gBonEnv.serializeFlags;
			deserializeFlags = gBonEnv.deserializeFlags;
			
			for (let pair in gBonEnv.serializeHandlers)
				serializeHandlers.Add(pair);

			mixin CloneDelegate(var del)
			{
				new Delegate()..SetFuncPtr(del.[Friend]mFuncPtr, del.[Friend]mTarget)
			}

			for (let pair in gBonEnv.instanceHandlers)
			{
				Delegate make = pair.value.make == null ? null : CloneDelegate!(pair.value.make);
				Delegate destroy = pair.value.destroy == null ? null : CloneDelegate!(pair.value.destroy);
				instanceHandlers.Add(pair.key, ((.)make, (.)destroy));
			}

			stringViewHandler = gBonEnv.stringViewHandler;
		}
	}
}