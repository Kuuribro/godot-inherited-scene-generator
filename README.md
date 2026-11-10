Inherited Scene Generator

A Godot 4 editor plugin for batch creation of Inherited Scenes from .glb files. This automates the need to create them manually for every imported asset.
Usage:

    In the FileSystem dock, select one or more .glb files and right-click.

    Choose "Generate Inherited Scene(s)" from the context menu.

    Select desired root folder to save these to. The folder structure underneath res://assets/... will be used, starting from the root the user selects.
	
	Material Override, if set, will set a material into the "Surface Material Override" setting of each mesh.

Only .glb files are used in this script currently. .fbx files unsupported.