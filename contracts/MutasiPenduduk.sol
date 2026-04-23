// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MutasiPenduduk
 * @dev Smart Contract untuk Pencatatan Log Keluar-Masuk Penduduk (Mutasi)
 * @notice Capstone Project - Smart Contract Technology
 * @author Sistem Kelurahan Digital
 *
 * Fitur Utama:
 * - Integritas Data: Setiap catatan mutasi tersimpan permanen di blockchain
 * - Verifikasi: Hanya petugas berwenang yang dapat mencatat mutasi
 * - Transparansi: Semua warga dapat melihat statistik kependudukan
 * - Otomatisasi: Statistik dihitung otomatis tanpa rekap manual
 */
contract MutasiPenduduk {

    // ─────────────────────────────────────────────
    //  ENUMERASI & STRUCT
    // ─────────────────────────────────────────────

    /// @dev Jenis mutasi penduduk
    enum JenisMutasi { MASUK, KELUAR }

    /// @dev Status verifikasi dokumen mutasi
    enum StatusVerifikasi { PENDING, DIVERIFIKASI, DITOLAK }

    /// @dev Data lengkap satu catatan mutasi
    struct CatatanMutasi {
        uint256 id;                   // ID unik mutasi
        string  nik;                  // NIK warga (16 digit)
        string  namaLengkap;          // Nama lengkap warga
        JenisMutasi jenis;            // MASUK atau KELUAR
        string  alamatAsal;           // Alamat sebelum mutasi
        string  alamatTujuan;         // Alamat sesudah mutasi
        string  alasanMutasi;         // Alasan pindah
        uint256 tanggalMutasi;        // Timestamp pencatatan
        address petugasPencatat;      // Alamat petugas yang mencatat
        StatusVerifikasi status;      // Status verifikasi
        string  nomorSuratPindah;     // Nomor dokumen resmi
        bool    aktif;                // Apakah catatan masih aktif
    }

    /// @dev Ringkasan statistik kependudukan lingkungan
    struct StatistikLingkungan {
        uint256 totalMasuk;
        uint256 totalKeluar;
        uint256 totalAktif;      // Warga yang saat ini berdomisili
        uint256 lastUpdated;
    }

    // ─────────────────────────────────────────────
    //  STATE VARIABLES
    // ─────────────────────────────────────────────

    address public immutable admin;          // Admin utama kontrak
    uint256 private counterMutasi;           // Penghitung ID mutasi
    string  public namaLingkungan;           // Nama RT/RW/Kelurahan

    mapping(uint256 => CatatanMutasi) private catatanMutasi;  // ID → catatan
    mapping(string  => uint256[])    private riwayatNIK;       // NIK → list ID mutasi
    mapping(address => bool)         public  petugasBerwenang; // Petugas terverifikasi
    mapping(string  => bool)         private nikTerdaftar;     // Cek duplikat aktif

    uint256[] private semuaIdMutasi;         // List semua ID mutasi
    StatistikLingkungan public statistik;    // Statistik real-time

    // ─────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────

    event MutasiMasukDicatat(
        uint256 indexed id,
        string  indexed nik,
        string  namaLengkap,
        uint256 tanggal,
        address petugas
    );

    event MutasiKeluarDicatat(
        uint256 indexed id,
        string  indexed nik,
        string  namaLengkap,
        uint256 tanggal,
        address petugas
    );

    event StatusDiperbarui(
        uint256 indexed id,
        StatusVerifikasi statusBaru,
        address oleh
    );

    event PetugasDidaftarkan(address indexed petugas, bool status);
    event StatistikDiperbarui(uint256 totalMasuk, uint256 totalKeluar, uint256 totalAktif);

    // ─────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────

    modifier hanyaAdmin() {
        require(msg.sender == admin, "Hanya admin yang dapat melakukan ini");
        _;
    }

    modifier hanyaPetugas() {
        require(
            petugasBerwenang[msg.sender] || msg.sender == admin,
            "Hanya petugas berwenang yang dapat mencatat mutasi"
        );
        _;
    }

    modifier idValid(uint256 _id) {
        require(_id > 0 && _id <= counterMutasi, "ID mutasi tidak valid");
        _;
    }

    modifier nikValid(string memory _nik) {
        require(bytes(_nik).length == 16, "NIK harus 16 digit");
        _;
    }

    // ─────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @dev Inisialisasi kontrak dengan nama lingkungan
     * @param _namaLingkungan Nama RT/RW/Kelurahan yang menggunakan sistem ini
     */
    constructor(string memory _namaLingkungan) {
        admin            = msg.sender;
        namaLingkungan   = _namaLingkungan;
        counterMutasi    = 0;

        // Admin otomatis menjadi petugas berwenang
        petugasBerwenang[msg.sender] = true;

        statistik = StatistikLingkungan({
            totalMasuk   : 0,
            totalKeluar  : 0,
            totalAktif   : 0,
            lastUpdated  : block.timestamp
        });
    }

    // ─────────────────────────────────────────────
    //  FUNGSI MANAJEMEN PETUGAS
    // ─────────────────────────────────────────────

    /**
     * @dev Daftarkan atau cabut akses petugas
     * @param _petugas Alamat wallet petugas
     * @param _status true = aktifkan, false = nonaktifkan
     */
    function kelolaPetugas(address _petugas, bool _status)
        external
        hanyaAdmin
    {
        require(_petugas != address(0), "Alamat tidak valid");
        petugasBerwenang[_petugas] = _status;
        emit PetugasDidaftarkan(_petugas, _status);
    }

    // ─────────────────────────────────────────────
    //  FUNGSI PENCATATAN MUTASI
    // ─────────────────────────────────────────────

    /**
     * @dev Catat warga yang MASUK ke lingkungan
     * @param _nik NIK warga (16 digit)
     * @param _namaLengkap Nama lengkap warga
     * @param _alamatAsal Alamat asal sebelum pindah
     * @param _alasanMutasi Alasan pindah masuk
     * @param _nomorSuratPindah Nomor dokumen surat pindah resmi
     */
    function catatMutasiMasuk(
        string memory _nik,
        string memory _namaLengkap,
        string memory _alamatAsal,
        string memory _alasanMutasi,
        string memory _nomorSuratPindah
    )
        external
        hanyaPetugas
        nikValid(_nik)
        returns (uint256)
    {
        require(bytes(_namaLengkap).length > 0,      "Nama tidak boleh kosong");
        require(bytes(_nomorSuratPindah).length > 0,  "Nomor surat wajib diisi");

        counterMutasi++;
        uint256 idBaru = counterMutasi;

        catatanMutasi[idBaru] = CatatanMutasi({
            id                : idBaru,
            nik               : _nik,
            namaLengkap       : _namaLengkap,
            jenis             : JenisMutasi.MASUK,
            alamatAsal        : _alamatAsal,
            alamatTujuan      : namaLingkungan,
            alasanMutasi      : _alasanMutasi,
            tanggalMutasi     : block.timestamp,
            petugasPencatat   : msg.sender,
            status            : StatusVerifikasi.PENDING,
            nomorSuratPindah  : _nomorSuratPindah,
            aktif             : true
        });

        riwayatNIK[_nik].push(idBaru);
        semuaIdMutasi.push(idBaru);
        nikTerdaftar[_nik] = true;

        // Update statistik
        statistik.totalMasuk++;
        statistik.totalAktif++;
        statistik.lastUpdated = block.timestamp;

        emit MutasiMasukDicatat(idBaru, _nik, _namaLengkap, block.timestamp, msg.sender);
        emit StatistikDiperbarui(statistik.totalMasuk, statistik.totalKeluar, statistik.totalAktif);

        return idBaru;
    }

    /**
     * @dev Catat warga yang KELUAR dari lingkungan
     * @param _nik NIK warga (16 digit)
     * @param _namaLengkap Nama lengkap warga
     * @param _alamatTujuan Alamat tujuan setelah pindah
     * @param _alasanMutasi Alasan pindah keluar
     * @param _nomorSuratPindah Nomor dokumen surat pindah resmi
     */
    function catatMutasiKeluar(
        string memory _nik,
        string memory _namaLengkap,
        string memory _alamatTujuan,
        string memory _alasanMutasi,
        string memory _nomorSuratPindah
    )
        external
        hanyaPetugas
        nikValid(_nik)
        returns (uint256)
    {
        require(bytes(_namaLengkap).length > 0,     "Nama tidak boleh kosong");
        require(bytes(_nomorSuratPindah).length > 0, "Nomor surat wajib diisi");

        counterMutasi++;
        uint256 idBaru = counterMutasi;

        catatanMutasi[idBaru] = CatatanMutasi({
            id                : idBaru,
            nik               : _nik,
            namaLengkap       : _namaLengkap,
            jenis             : JenisMutasi.KELUAR,
            alamatAsal        : namaLingkungan,
            alamatTujuan      : _alamatTujuan,
            alasanMutasi      : _alasanMutasi,
            tanggalMutasi     : block.timestamp,
            petugasPencatat   : msg.sender,
            status            : StatusVerifikasi.PENDING,
            nomorSuratPindah  : _nomorSuratPindah,
            aktif             : true
        });

        riwayatNIK[_nik].push(idBaru);
        semuaIdMutasi.push(idBaru);

        // Update statistik
        statistik.totalKeluar++;
        if (statistik.totalAktif > 0) statistik.totalAktif--;
        statistik.lastUpdated = block.timestamp;

        emit MutasiKeluarDicatat(idBaru, _nik, _namaLengkap, block.timestamp, msg.sender);
        emit StatistikDiperbarui(statistik.totalMasuk, statistik.totalKeluar, statistik.totalAktif);

        return idBaru;
    }

    // ─────────────────────────────────────────────
    //  FUNGSI VERIFIKASI
    // ─────────────────────────────────────────────

    /**
     * @dev Perbarui status verifikasi dokumen mutasi
     * @param _id ID catatan mutasi
     * @param _status Status verifikasi baru
     */
    function perbaruiStatusVerifikasi(uint256 _id, StatusVerifikasi _status)
        external
        hanyaPetugas
        idValid(_id)
    {
        require(catatanMutasi[_id].aktif, "Catatan tidak aktif");
        catatanMutasi[_id].status = _status;
        emit StatusDiperbarui(_id, _status, msg.sender);
    }

    // ─────────────────────────────────────────────
    //  FUNGSI BACA (VIEW)
    // ─────────────────────────────────────────────

    /**
     * @dev Ambil detail satu catatan mutasi berdasarkan ID
     */
    function getCatatanMutasi(uint256 _id)
        external
        view
        idValid(_id)
        returns (CatatanMutasi memory)
    {
        return catatanMutasi[_id];
    }

    /**
     * @dev Ambil semua ID mutasi milik satu NIK
     */
    function getRiwayatNIK(string memory _nik)
        external
        view
        returns (uint256[] memory)
    {
        return riwayatNIK[_nik];
    }

    /**
     * @dev Cek apakah NIK terdaftar aktif di lingkungan
     */
    function cekNIKAktif(string memory _nik)
        external
        view
        returns (bool)
    {
        return nikTerdaftar[_nik];
    }

    /**
     * @dev Ambil total jumlah catatan mutasi
     */
    function getTotalMutasi() external view returns (uint256) {
        return counterMutasi;
    }

    /**
     * @dev Ambil statistik kependudukan lengkap
     */
    function getStatistik()
        external
        view
        returns (
            uint256 totalMasuk,
            uint256 totalKeluar,
            uint256 totalAktif,
            uint256 lastUpdated,
            string memory lingkungan
        )
    {
        return (
            statistik.totalMasuk,
            statistik.totalKeluar,
            statistik.totalAktif,
            statistik.lastUpdated,
            namaLingkungan
        );
    }

    /**
     * @dev Ambil daftar ID mutasi dengan pagination
     * @param _offset Indeks awal
     * @param _limit Jumlah data yang diambil
     */
    function getListMutasi(uint256 _offset, uint256 _limit)
        external
        view
        returns (uint256[] memory ids, uint256 total)
    {
        total = semuaIdMutasi.length;
        if (_offset >= total) {
            return (new uint256[](0), total);
        }

        uint256 end   = _offset + _limit > total ? total : _offset + _limit;
        uint256 count = end - _offset;
        ids = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            ids[i] = semuaIdMutasi[_offset + i];
        }
    }
}
