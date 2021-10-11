var app = Vue.createApp({});

app.component('header-bar', {
    template: `
        <div class="header">
            <div class="tools">
                <a @click="reload">Reload Videos</a>
            </div>
            <h1>Carflix</h1>
        </div>
    `,
    methods: {
        async reload() {
            await fetch('/reload', {
                method: 'post',
            });
            this.$router.go();
        }
    }
});

app.component('show-list', {
    data() {
        return {
            shows: []
        }
    },
    created() {
        const getShows = async () => {
            let response = await fetch('/shows', {
                method: 'get',
                headers: {
                    'content-type': 'application/json'
                }
            });
            this.shows = await response.json();
        }
        getShows();
    },
    template: `
        <div class="show-list">
            <div class="show-tile" v-for="show in shows">
                <show-thumb
                    :id="show.id"
                    :title="show.title"
                    :thumb="show.thumb"></show-thumb>
            </div>
        </div>
    `
});

app.component('show-thumb', {
    props: ['id', 'title'],
    template: `
        <div class="show-thumb" :style="{ backgroundImage: 'url(' + thumbUrl + ')' }" @click="play(show)">
            <div class="info">
                <span class="title">{{ title }}</span>
            </div>
        </div>
    `,
    computed: {
        thumbUrl() {
            return `/shows/${this.id}/thumb`;
        },
    },
    methods: {
        play() {
            this.$router.push(`/shows/${this.id}`);
        }
    },
});

app.component('show-detail', {
    props: ['id'],
    data() {
        return {
            title: "",
            thumb: "",
            episodes: [],
            isMovie: false,
        }
    },
    computed: {
        thumbUrl() {
            return `/shows/${this.id}/thumb`;
        },
    },
    template: `
        <div class="show-details">
            <img :src="thumbUrl" class="thumb">

            <h2 class="title">{{ title }}</h2>

            <div v-if="isMovie" class="episode-list">
                <div class="episode" @click="watch(1)">Watch now</div>
            </div>

            <div v-if="!isMovie" class="episode-list">
                <div v-for="ep in episodes">
                    <div class="episode" @click="watch(ep.id)">{{ ep.title }}</div>
                </div>
            </div>
        </div>
    `,
    created() {
        this.fetchShow(this.id);
    },
    methods: {
        async fetchShow(id) {
            let response = await fetch(`/shows/${id}`, {
                method: 'get',
                headers: {
                    'content-type': 'application/json'
                }
            });
            let show = await response.json();
            for (k in show) {
                if (k == 'id') continue;
                this[k] = show[k];
            }
        },
        watch(vid) {
            this.$router.push(`/watch/${this.id}/${vid}`);
        },
    },
});

app.component('video-player', {
    props: ['url'],
    template: `<video :src="url" ref="vid" autoplay controls class="video-player">`
});



const HomePage = {
    template: `
        <header-bar />
        <div class="body">
            <show-list />
        </div>
    `
}

const ShowPage = {
    template: `
        <header-bar />
        <div class="body">
            <show-detail :id="this.$route.params.sid" />
        </div>
    `,
};

const VideoPage = {
    data() {
        return {
            url: `/shows/${this.$route.params.sid}/episodes/${this.$route.params.vid}/video`
        }
    },
    template: `<video-player :url="url" />`,
};


const routes = [
    { path: '/', component: HomePage },
    { path: '/shows/:sid', component: ShowPage },
    { path: '/watch/:sid/:vid', component: VideoPage },
];

const router = VueRouter.createRouter({
    history: VueRouter.createWebHashHistory(),
    routes,
})
app.use(router);

app.mount('#app');
