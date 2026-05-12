using System;
using System.Diagnostics;
using System.IO;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        string launcherDir = AppDomain.CurrentDomain.BaseDirectory;
        string gamePath = Path.Combine(launcherDir, "Dead Spark.exe");

        if (!File.Exists(gamePath))
        {
            gamePath = @"D:\Games\FixPatches\DeadSpark\Dead Spark.exe";
        }

        if (!File.Exists(gamePath))
        {
            Console.Error.WriteLine("Dead Spark.exe not found. Put this launcher next to the game executable.");
            return 1;
        }

        string defaultArgs = "--rendering-driver opengl3 --rendering-method compatibility";
        string extraArgs = args != null && args.Length > 0 ? " " + string.Join(" ", args) : string.Empty;

        var psi = new ProcessStartInfo
        {
            FileName = gamePath,
            Arguments = defaultArgs + extraArgs,
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(gamePath) ?? launcherDir
        };

        try
        {
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Failed to launch game: " + ex.Message);
            return 2;
        }
    }
}
