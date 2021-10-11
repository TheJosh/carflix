package main

import (
    "path"
    "strconv"
    "fmt"
    "os"
    "flag"
    "strings"
    "os/exec"
    "io/ioutil"
    "net/http"
    "github.com/gin-gonic/gin"
)


type episode struct {
    ID string `json:"id"`
    Title string `json:"title"`
    Filename string `json:"-"`
}

type show struct {
    ID string `json:"id"`
    Title string `json:"title"`
    Episodes []episode `json:"-"`
    Thumb string `json:"-"`
}

var shows = []show{}
var nextShowId = 0

func findAllContent() {
    shows = make([]show, 0, 32)
    nextShowId = 0

    // Local content directory
    findDirContent("../content/")

    // Videos directory within the homedir
    // Might not exist, which will be silently be ignored
    dirname, err := os.UserHomeDir()
    if err == nil {
        findDirContent(dirname + "/Videos/")
    }

    // Use lsblk to find all mounted storage
    cmd := exec.Command("lsblk", "--output=PATH,RM,MOUNTPOINT", "--raw", "--noheading")
    out, err := cmd.Output()
    if err != nil {
        fmt.Println(err)
        return
    }

    lines := strings.Split(string(out), "\n")
    for _, ln := range lines {
        fields := strings.Split(ln, " ")

        if len(fields) != 3 { continue }    // got three columns from lsblk
        if fields[1] != "1" { continue }    // removable only
        if fields[2] == "" { continue }     // mounted only

        fmt.Printf("Found external device %s mounted at %s\n", fields[0], fields[2])
        findDirContent(fields[2] + "/")
    }

    fmt.Printf("Content indexing complete\n")
}

func findDirContent(dir string) {
    files, err := ioutil.ReadDir(dir)
    if err != nil {
        fmt.Println("Unable to read content directory:", err)
        return
    }

    for _, file := range files {
        if file.Name()[0] == '.' {
            continue
        }

        if file.IsDir() {
            s := findShowContent(dir + file.Name())
            if len(s.Episodes) > 0 {
                shows = append(shows, s)
            }
        }
    }
}

func findShowContent(dir string) (show) {
    fmt.Println("Scanning", dir)

    files, err := ioutil.ReadDir(dir)
    if err != nil {
        fmt.Println("  ", err)
        return show{}
    }

    eps := []episode{}
    epid := 0;
    for _, file := range files {
        if file.Name()[0] == '.' {
            continue
        }

        ext := path.Ext(file.Name())
        if ext != ".mp4" {
            continue
        }

        epid += 1
        eps = append(eps, episode{
            ID: strconv.Itoa(epid),
            Title: path.Base(file.Name()),
            Filename: dir + "/" + file.Name(),
        })

        fmt.Println("  Added:", file.Name())
    }

    if epid == 0 {
        fmt.Println("  No episodes found!")
        return show{}
    }

    nextShowId += 1;
    s := show{
        ID: strconv.Itoa(nextShowId),
        Title: path.Base(dir),
        Episodes: eps,
    }

    // Use a thumb if it exists, or an "autothumb" auto-generated file
    if _, err := os.Stat(dir + "/thumb.jpg"); err == nil {
        s.Thumb = dir + "/thumb.jpg"
    } else if _, err := os.Stat(dir + "/autothumb.jpg"); err == nil {
        s.Thumb = dir + "/autothumb.jpg"
    } else {
        createThumb(s, dir);
        s.Thumb = dir + "/autothumb.jpg"
    }

    return s;
}

func createThumb(s show, dir string) {
    fmt.Println("  Creating thumbnail")

    capTime := 15;
    if len(s.Episodes) == 1 {
        capTime = 90     // movies have more logos
    }

    cmd := exec.Command(
        "ffmpeg",
        "-i", s.Episodes[0].Filename,
        "-ss", strconv.Itoa(capTime),
        "-vf", "thumbnail,scale=640:-1",
        "-frames:v", "1",
        dir + "/autothumb.jpg",
    )
    err := cmd.Run()

    if err != nil {
        fmt.Println("  ffmpeg error:", err)
    }
}


func getShow(id string) (*show) {
    for _, a := range shows {
        if a.ID == id {
            return &a;
        }
    }
    return nil
}

func getEpisode(show show, id string) (*episode) {
    for _, a := range show.Episodes {
        if a.ID == id {
            return &a;
        }
    }
    return nil
}


func main() {
    bindAddr := flag.String(
        "bind", "localhost:8080",
        "Address to bind to in [address]:port format. If address is not supplied then all addresses are bound.",
    )
    flag.Parse()

    findAllContent()
    fmt.Println()

    router := gin.Default()
    router.StaticFile("/", "../assets/index.htm")
    router.Static("/assets", "../assets")
    router.Static("/vendor", "../vendor")
    router.POST("/reload", reload)
    router.GET("/shows", getShows)
    router.GET("/shows/:sid", getShowByID)
    router.GET("/shows/:sid/thumb", getShowThumb)
    router.GET("/shows/:sid/episodes/:vid/video", getEpisodeVideoByID)

    router.Run(*bindAddr)
}


// Fetch all available shows. Excludes some internal details
func reload(c *gin.Context) {
    findAllContent();
    c.IndentedJSON(http.StatusOK, map[string]interface{}{
        "num-shows": len(shows),
    })
}

// Fetch all available shows. Excludes some internal details
func getShows(c *gin.Context) {
    c.IndentedJSON(http.StatusOK, shows)
}

// Fetch details of a single show, including episodes
func getShowByID(c *gin.Context) {
    sid := c.Param("sid")
    show := getShow(sid)
    if show == nil {
        c.IndentedJSON(http.StatusNotFound, gin.H{"message": "not found"})
        return
    }

    fullShow := map[string]interface{}{
        "id": show.ID,
        "title": show.Title,
        "thumb": show.Thumb,
        "episodes": show.Episodes,
        "isMovie": len(show.Episodes) == 1,
    }

    c.IndentedJSON(http.StatusOK, fullShow)
}

// Return the thumb for a given show
func getShowThumb(c *gin.Context) {
    sid := c.Param("sid")
    show := getShow(sid)
    if show == nil {
        c.IndentedJSON(http.StatusNotFound, gin.H{"message": "not found"})
        return
    }

    c.File((*show).Thumb)
}

// Return the video for a given episode
func getEpisodeVideoByID(c *gin.Context) {
    sid := c.Param("sid")
    show := getShow(sid)
    if show == nil {
        c.IndentedJSON(http.StatusNotFound, gin.H{"message": "not found"})
        return
    }

    vid := c.Param("vid")
    episode := getEpisode(*show, vid)
    if episode == nil {
        c.IndentedJSON(http.StatusNotFound, gin.H{"message": "not found"})
        return
    }

    c.File((*episode).Filename)
}
