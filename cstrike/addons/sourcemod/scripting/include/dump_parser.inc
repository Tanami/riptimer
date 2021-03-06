#if defined _output_dump_parser_defined_
#endinput
#endif
#define _output_dump_parser_defined_

#define OUTPUT_SIZE 2048
#define MEMBER_SIZE 128

// #define DEBUG

#if defined DEBUG
	#define LOG(%1) LogMessage(%1)
#else
	#define LOG(%1) DoNothing(%1)
#endif

// Used to keep temporary files for debugging
// #define NO_DEL

enum
{
	OUTPUTTYPE,
	TARGETENTITY,
	OUTPUTNAME,
	PARAMETERS,
	DELAY,
	ONCE,
	OUTPUTSIZE
};

enum struct Output
{
	char Output[MEMBER_SIZE];// OnStartTouch
	char Target[MEMBER_SIZE];// !Activator 
	char Input[MEMBER_SIZE];// Addoutput
	char Parameters[MEMBER_SIZE];// gravity 0.1
	float Delay;// 0.1
	bool Once;// 0

	void Dump()
	{
		PrintToServer("output: %s\ntarget: %s\ninput: %s\nParameters: %s\ndelay: %f\nonce: %i", this.Output, this.Target, this.Input, this.Parameters, this.Delay, this.Once);
	}
	
	void ToString(char[] input, int length = OUTPUT_SIZE)
	{
		Format(input, length, "%s;%s;%s;%s;%f;%i", this.Output, this.Target, this.Input, this.Parameters, this.Delay, this.Once);
	}

	void Parse(char[] buffer)
	{
		// Break it up into more managable parts
		char entity[OUTPUTSIZE][64];
		ExplodeString(buffer, ";", entity, OUTPUTSIZE, 64);

		strcopy(this.Output, MEMBER_SIZE, entity[OUTPUTTYPE]);
		strcopy(this.Target, MEMBER_SIZE, entity[TARGETENTITY]);
		strcopy(this.Input, MEMBER_SIZE, entity[OUTPUTNAME]);
		strcopy(this.Parameters, MEMBER_SIZE, entity[PARAMETERS]);
		this.Delay = StringToFloat(entity[DELAY]);
		this.Once = (StringToInt(entity[ONCE]) > 0);
	}
}

enum struct Entity
{
	char HammerID[MEMBER_SIZE];
	float Wait;
	char Classname[MEMBER_SIZE];
	ArrayList OutputList;

	void Dump()
	{
		char b[OUTPUT_SIZE];
		for(int i = 0; i < this.OutputList.Length; ++i)
		{
			Output temp;
			this.OutputList.GetArray(i, temp);
			char buffer[OUTPUT_SIZE];
			temp.ToString(buffer);
			Format(b, OUTPUT_SIZE, "\t\t%s\n\t\t%s", b, buffer);
		}
		PrintToServer("\n\"%s\"\n{\n\t\"wait\" \"%f\"\n\t\"classname\" \"%s\"\n\t\"outputs\"\n\t{\n\t%s\n\t}\n}\n", this.HammerID, this.Wait, this.Classname, b);
	}

	void ToString(char[] input, int length = OUTPUT_SIZE)
	{
		char outputs[OUTPUT_SIZE];
		for(int i = 0; i < this.OutputList.Length; ++i)
		{
			Output temp;
			this.OutputList.GetArray(i, temp);
			char buffer[OUTPUT_SIZE];
			temp.ToString(buffer);
			Format(outputs, OUTPUT_SIZE, "%s|%s", outputs, buffer);
		}
		Format(input, length, "%s;%f;%s;{%s}", this.HammerID, this.Wait, this.Classname, outputs);
	}

	void CleanUp()
	{
		delete this.OutputList;
	}
}

/* *
*	Stock function to copy all the data from one 'Output' to another
*	Since there's no handles nothing will need to be freed.
*	
*	return: noreturn
* */
stock void CloneOutput(const Output input, Output out)
{
	strcopy(out.Output, MEMBER_SIZE, input.Output);
	strcopy(out.Target, MEMBER_SIZE, input.Target);
	strcopy(out.Input, MEMBER_SIZE, input.Input);
	strcopy(out.Parameters, MEMBER_SIZE, input.Parameters);
	out.Delay = input.Delay;
	out.Once = input.Once;
}

/* *
*	Stock function to copy all the data from one 'Entity' to another
*	Output ArrayLists are copies as well and need to be freed.
*	
*	return: noreturn
* */
stock void CloneEntity(const Entity input, Entity out, Handle newOwner = null)
{
	strcopy(out.HammerID, MEMBER_SIZE, input.HammerID);
	out.Wait = input.Wait;
	strcopy(out.Classname, MEMBER_SIZE, input.Classname);
	if(newOwner != null)
	{
		out.OutputList = view_as<ArrayList>(CloneHandle(input.OutputList.Clone(), newOwner));
	}
	else
	{
		out.OutputList = input.OutputList.Clone();
	}
}

/* *
*	Fired when either JSON Dump file is found or is fully parsed.
*	
*	return: noreturn
* */
forward void OnDumpFileReady();

/* *
*	Fired when everything is processed and it's safe to call natives.
*	
*	return: noreturn
* */
forward void OnDumpFileProcessed();

/* *
*	Retrieves a copy of the 'Entity' enum struct, as an any array, for the given entity index.
*	The ArrayList will not be cleared automatically.
*	Use the GetDumpEntity stock instead.
*	
*	Param: index		Entity index.
*	Param: entity		Entity enum struct as an any array if found.
*	
*	return: true if successful, false otherwise.
* */
native bool GetDumpEntityAsArray(int index, any[] entity);

/* *
*	Retrieves a copy of the 'Entity' enum struct for the given entity index and places it inside an ArrayList.
*	The ArrayList will not be cleared automatically.
*	Use the GetDumpEntity stock instead.
*	
*	Param: index		Entity index.
*	Param: entity 		Entity enum struct as generic any array
*	
*	return: true if successful, false otherwise.
* */
native ArrayList GetDumpEntityAsList(int index);

/* *
*	Retrieves a copy of the 'Entity' enum struct for the given index.
*	
*	Param: index		Entity index.
*	Param: ent			Entity enum struct if found.
*	
*	return: true if successful, false otherwise.
* */
stock bool GetDumpEntity(int index, Entity ent)
{
	return GetDumpEntityAsArray(index, ent);
}

/* *
*	Retrieves a copy of the 'Entity' enum struct from the given hammer id and places it inside an ArrayList.
*	The ArrayList will not be cleared automatically.
*	Use the GetDumpEntity2 stock instead.
*	
*	Param: hammerid		Hammer id of the entity.
*	
*	return: ArrayList containing the Entity enum struct if found, INVALID_HANDLE otherwise.
* */
native ArrayList GetDumpEntityFromID(int hammerid);

/* *
*	Retrieves a copy of the 'Entity' enum struct from the given hammer id.
*	The ArrayList will not be cleared automatically.
*	Use the GetDumpEntity2 stock instead.
*	
*	Param: hammerid		Hammer id of the entity.
*	Param: entity 		Entity enum struct as generic any array
*	
*	return: true if successful, false otherwise.
* */
native bool GetDumpEntityFromIDAsArray(int hammerid, any[] entity);

/* *
*	Retrieves a copy of the 'Entity' enum struct for the given hammer id.
*	
*	Param: hammerid		Hammer id of the entity.
*	Param: ent			Entity enum struct if found.
*	
*	return: true if successful, false otherwise.
* */
stock bool GetDumpEntity2(int hammerid, Entity ent)
{
	return GetDumpEntityFromIDAsArray(hammerid, ent);
}

/* *
*	Retrieves a copy of all the entities inside an ArrayList
*	The ArrayList will not be cleared automatically.
*	
*	
*	return: ArrayList full of 'Entities' if successful, INVALID_HANDLE otherwise.
* */
native ArrayList GetDumpEntities();

/* *
*	Retrieves a copy of the StringMap that holds the indexes of the entities.
*	Hammer ids are the keys and the cells are the index in the entity dump
*	The StringMap will not be cleared automatically.
*	
*	
*	return: StringMap full of keys if successful, INVALID_HANDLE otherwise.
* */
native StringMap GetDumpStringMap();

/* *
*	Returns whether or not it's safe to call any natives
*	
*	return: gB_Ready.
* */
native bool IsDumpReady();

///////////////////////////////////////////////////////////
// OutputInfo stocks used for use in plugins that use it //
//			I do not recommend using these				 //
///////////////////////////////////////////////////////////

/* *
*	Retrieves the number of outputs that have the given trigger
*	
*	Param: index		Ent index of the entity.
*	Param: output		Output that you want to count. ("OnStartTouch" or empty for all)
*	
*	return: Output count
* */
stock int GetOutputCount(int index, const char[] output = "")
{
	Entity ent;
	if(!GetDumpEntity(index, ent))
	{
		return -1;
	}

	int count = 0;
	if(output[0] == 0)
	{
		count = ent.OutputList.Length;
	}
	else
	{
		for(int i = 0; i < ent.OutputList.Length; ++i)
		{
			Output out;
			ent.OutputList.GetArray(i, out);
			if(StrEqual(output, out.Output, false))
			{
				++count;
			}
		}
	}
	ent.CleanUp();
	return count;
}

/* *
*	Retrieves the target at the current index for the given output.
*	Not recommended as outputs aren't organized and aren't guarenteed to be the same between sessions and servers.
*	
*	Param: index		Ent index of the entity.
*	Param: output		Output that you want to count. ("OnStartTouch" or empty for all)
*	Param: num			Index/occurance of that given output to return
*	Param: target		Buffer to store the outputs target
*	Param: length		Size of the buffer, default is the max size of the enum structs members
*	
*	return: True if operation was successful, false otherwise.
* */
stock bool GetOutputTarget(int index, const char[] output, int num, char[] target, int length = MEMBER_SIZE)
{
	Entity ent;
	if(!GetDumpEntity(index, ent))
	{
		return false;
	}
	

	int count = 0;
	bool ret = false;
	char buffer[MEMBER_SIZE];
	if(StrContains(output, "m_") == 0)
	{
		strcopy(buffer, MEMBER_SIZE, output[2]);
	}
	else
	{
		strcopy(buffer, MEMBER_SIZE, output);
	}

	for(int i = 0; i < ent.OutputList.Length; ++i)
	{
		Output out;
		ent.OutputList.GetArray(i, out);
		if(StrEqual(buffer, out.Output, false))
		{
			if(count++ == num)
			{
				strcopy(target, length, out.Target);
				ret = true
				break;
			}
		}
	}

	ent.CleanUp();
	return ret;
}

/* *
*	Retrieves the input at the current index for the given output.
*	Not recommended as outputs aren't organized and aren't guarenteed to be the same between sessions and servers.
*	
*	Param: index		Ent index of the entity.
*	Param: output		Output that you want to count. ("OnStartTouch" or empty for all)
*	Param: num			Index/occurance of that given output to return
*	Param: input		Buffer to store the targets input
*	Param: length		Size of the buffer, default is the max size of the enum structs members
*	
*	return: True if operation was successful, false otherwise.
* */
stock bool GetOutputTargetInput(int index, const char[] output, int num, char[] input, int length = MEMBER_SIZE)
{
	Entity ent;
	if(!GetDumpEntity(index, ent))
	{
		return false;
	}

	int count = 0;
	bool ret = false;
	char buffer[MEMBER_SIZE];
	if(StrContains(output, "m_") == 0)
	{
		strcopy(buffer, MEMBER_SIZE, output[2]);
	}
	else
	{
		strcopy(buffer, MEMBER_SIZE, output);
	}

	for(int i = 0; i < ent.OutputList.Length; ++i)
	{
		Output out;
		ent.OutputList.GetArray(i, out);
		if(StrEqual(buffer, out.Output, false))
		{
			if(count++ == num)
			{
				strcopy(input, length, out.Input);
				ret = true
				break;
			}
		}
	}

	ent.CleanUp();
	return ret;
}

/* *
*	Retrieves the output parameters at the current index for the given output.
*	Not recommended as outputs aren't organized and aren't guarenteed to be the same between sessions and servers.
*	
*	Param: index		Ent index of the entity.
*	Param: output		Output that you want to count. ("OnStartTouch" or empty for all)
*	Param: num			Index/occurance of that given output to return
*	Param: parameters	Buffer to store the outputs parameters
*	Param: length		Size of the buffer, default is the max size of the enum structs members
*	
*	return: True if operation was successful, false otherwise.
* */
stock bool GetOutputParameter(int index, const char[] output, int num, char[] parameters, int length = MEMBER_SIZE)
{
	Entity ent;
	if(!GetDumpEntity(index, ent))
	{
		return false;
	}

	int count = 0;
	bool ret = false;
	char buffer[MEMBER_SIZE];
	if(StrContains(output, "m_") == 0)
	{
		strcopy(buffer, MEMBER_SIZE, output[2]);
	}
	else
	{
		strcopy(buffer, MEMBER_SIZE, output);
	}

	for(int i = 0; i < ent.OutputList.Length; ++i)
	{
		Output out;
		ent.OutputList.GetArray(i, out);
		if(StrEqual(buffer, out.Output, false))
		{
			if(count++ == num)
			{
				strcopy(parameters, length, out.Parameters);
				ret = true
				break;
			}
		}
	}

	ent.CleanUp();
	return ret;
}

/* *
*	Retrieves the output delay at the current index for the given output.
*	Not recommended as outputs aren't organized and aren't guarenteed to be the same between sessions and servers.
*	
*	Param: index		Ent index of the entity.
*	Param: output		Output that you want to count. ("OnStartTouch" or empty for all)
*	Param: num			Index/occurance of that given output to return
*	
*	return: output delay
* */
stock float GetOutputDelay(int index, const char[] output, int num)
{
	Entity ent;
	if(!GetDumpEntity(index, ent))
	{
		return -1.0;
	}
	
	float delay = 0.0;
	int count = 0;
	char buffer[MEMBER_SIZE];
	if(StrContains(output, "m_") == 0)
	{
		strcopy(buffer, MEMBER_SIZE, output[2]);
	}
	else
	{
		strcopy(buffer, MEMBER_SIZE, output);
	}

	for(int i = 0; i < ent.OutputList.Length; ++i)
	{
		Output out;
		ent.OutputList.GetArray(i, out);
		if(StrEqual(buffer, out.Output, false))
		{
			if(count++ == num)
			{
				delay = out.Delay;
				break;
			}
		}
	}

	ent.CleanUp();
	return delay;
}

public SharedPlugin __pl_output_dump_parser =
{
	name = "output_dump_parser",
	file = "dump_parser.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_output_dump_parser_SetNTVOptional()
{
	MarkNativeAsOptional("GetDumpStringMap");
	MarkNativeAsOptional("GetDumpEntityAsList");
	MarkNativeAsOptional("GetDumpEntityAsArray");
	MarkNativeAsOptional("GetDumpEntityFromID");
	MarkNativeAsOptional("GetDumpEntityFromIDAsArray");
	MarkNativeAsOptional("GetDumpEntities");
	MarkNativeAsOptional("IsDumpReady");
}
#endif

///////////////////////////////////////////
// Generic stocks used inside the plugin //
///////////////////////////////////////////

stock bool StringContains(const char[] str, const char[] sub, bool caseSense = false)
{
	return (StrContains(str, sub, caseSense) != -1);
}

stock bool GetKVString(KeyValues kv, char[] input, char[] output, int length)
{
	kv.GetString(input, output, length);

	return (kv.GetDataType(input) != KvData_None);
}

stock int GetHammerFromIndex(int index)
{
	if(!IsValidEntity(index))
	{
		return 0;
	}

	return GetEntProp(index, Prop_Data, "m_iHammerID");
}

stock void DoNothing(const char[] nothing)
{
}